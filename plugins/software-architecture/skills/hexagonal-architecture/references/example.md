# Worked example: booking a session

One capability, end to end: the domain rule, the use case and its ports, a
driven adapter over a SQL store, an HTTP handler as the driving adapter, a
write hook as a second driving adapter, the composition root, and the tests.
Names are illustrative; every import is the example's own.

## Domain and use case (inside)

```ts
// src/bookings/domain/booking.ts
export class Booking {
  private constructor(
    readonly id: string,
    readonly slotId: string,
    readonly email: string,
    readonly createdAt: Date,
  ) {}

  static create(input: { id: string; slotId: string; email: string }, now: Date): Booking {
    if (!input.email.includes("@")) throw new InvalidBooking("email");
    return new Booking(input.id, input.slotId, input.email.toLowerCase(), now);
  }
}

export class InvalidBooking extends Error {
  constructor(readonly field: string) {
    super(`invalid ${field}`);
  }
}
```

```ts
// src/bookings/application/ports.ts
import type { Booking } from "../domain/booking";

export interface BookingRepository {
  countForSlot(tenantId: string, slotId: string): Promise<number>;
  save(tenantId: string, booking: Booking): Promise<void>;
}
export interface Clock { now(): Date }
export interface IdGenerator { next(): string }
```

```ts
// src/bookings/application/book-session.ts
import { Booking } from "../domain/booking";
import type { BookingRepository, Clock, IdGenerator } from "./ports";

export type BookSessionCommand = {
  tenantId: string;
  slotId: string;
  capacity: number;
  email: string;
};
export type BookSessionResult =
  | { ok: true; bookingId: string }
  | { ok: false; reason: "slot-full" };

export function makeBookSession(deps: {
  bookings: BookingRepository;
  clock: Clock;
  ids: IdGenerator;
}) {
  return async (cmd: BookSessionCommand): Promise<BookSessionResult> => {
    const taken = await deps.bookings.countForSlot(cmd.tenantId, cmd.slotId);
    if (taken >= cmd.capacity) return { ok: false, reason: "slot-full" };
    const booking = Booking.create(
      { id: deps.ids.next(), slotId: cmd.slotId, email: cmd.email },
      deps.clock.now(),
    );
    await deps.bookings.save(cmd.tenantId, booking);
    return { ok: true, bookingId: booking.id };
  };
}
```

The count-then-save is not atomic: two requests can both see one seat left.
Where that matters, the port grows a method the adapter can make atomic
(`reserveSeat`), or a unique constraint backs it. The port names the need;
the adapter picks the mechanism.

## Driven adapters (outside)

```ts
// src/bookings/adapters/sql-booking-repository.ts
import type { BookingRepository } from "../application/ports";
import type { Booking } from "../domain/booking";

export interface SqlClient {
  query<T>(text: string, params: readonly unknown[]): Promise<T[]>;
}

export class SqlBookingRepository implements BookingRepository {
  constructor(private readonly db: SqlClient) {}

  async countForSlot(tenantId: string, slotId: string): Promise<number> {
    const rows = await this.db.query<{ count: number }>(
      "SELECT count(*)::int AS count FROM bookings WHERE tenant_id = $1 AND slot_id = $2",
      [tenantId, slotId],
    );
    return rows[0]?.count ?? 0;
  }

  async save(tenantId: string, booking: Booking): Promise<void> {
    await this.db.query(
      "INSERT INTO bookings (id, tenant_id, slot_id, email, booked_at) VALUES ($1, $2, $3, $4, $5)",
      [booking.id, tenantId, booking.slotId, booking.email, booking.createdAt.toISOString()],
    );
  }
}
```

```ts
// src/bookings/adapters/in-memory-booking-repository.ts
import type { BookingRepository } from "../application/ports";
import type { Booking } from "../domain/booking";

export class InMemoryBookingRepository implements BookingRepository {
  private readonly rows: { tenantId: string; booking: Booking }[] = [];

  async countForSlot(tenantId: string, slotId: string) {
    return this.rows.filter((r) => r.tenantId === tenantId && r.booking.slotId === slotId).length;
  }
  async save(tenantId: string, booking: Booking) {
    this.rows.push({ tenantId, booking });
  }
}
```

## Composition root

```ts
// src/composition.ts
import { makeBookSession } from "./bookings/application/book-session";
import { SqlBookingRepository } from "./bookings/adapters/sql-booking-repository";
import { db } from "./db";

export function bookSession() {
  return makeBookSession({
    bookings: new SqlBookingRepository(db),
    clock: { now: () => new Date() },
    ids: { next: () => crypto.randomUUID() },
  });
}
```

## Driving adapters (outside)

An HTTP handler, a function `(request: Request) => Promise<Response>`: parse,
call, map. The tenant comes from whatever the front resolves it from (host,
path); that resolution belongs to the adapter.

```ts
// src/routes/bookings.ts
import { bookSession } from "../composition";
import { InvalidBooking } from "../bookings/domain/booking";
import { resolveTenant } from "../tenancy/resolve-tenant";

export async function postBooking(request: Request): Promise<Response> {
  const body = await request.json();
  const tenantId = await resolveTenant(request);
  try {
    const result = await bookSession()({ ...body, tenantId });
    if (!result.ok) return problem(409, "slot-full", "The slot is full.");
    return Response.json({ id: result.bookingId }, { status: 201 });
  } catch (err) {
    if (err instanceof InvalidBooking) return problem(422, "invalid-booking", err.message);
    throw err;
  }
}

function problem(status: number, type: string, detail: string) {
  return Response.json(
    { type: `/problems/${type}`, title: detail, status, detail },
    { status, headers: { "Content-Type": "application/problem+json" } },
  );
}
```

The error body follows the `rest-api-design` skill. A write hook on the
bookings store that calls `Booking.create` (or a scheduled job that imports
bookings from a file) is a second driving adapter: it makes the same rule hold
for writes from an admin UI or a generated API, which never pass through the
HTTP handler.

## Tests

```ts
// src/bookings/application/book-session.test.ts
import { makeBookSession } from "./book-session";
import { InMemoryBookingRepository } from "../adapters/in-memory-booking-repository";

const fixed = { now: () => new Date("2026-01-01T10:00:00Z") };
let n = 0;
const ids = { next: () => `b-${++n}` };

describe("book session", () => {
  it("refuses a booking once the slot is full", async () => {
    const book = makeBookSession({ bookings: new InMemoryBookingRepository(), clock: fixed, ids });
    const cmd = { tenantId: "t1", slotId: "s1", capacity: 1, email: "a@b.c" };

    expect(await book(cmd)).toMatchObject({ ok: true });
    expect(await book(cmd)).toEqual({ ok: false, reason: "slot-full" });
  });

  it("counts seats per tenant", async () => {
    const book = makeBookSession({ bookings: new InMemoryBookingRepository(), clock: fixed, ids });
    await book({ tenantId: "t1", slotId: "s1", capacity: 1, email: "a@b.c" });

    expect(await book({ tenantId: "t2", slotId: "s1", capacity: 1, email: "a@b.c" }))
      .toMatchObject({ ok: true });
  });
});
```

A contract suite — a function taking a factory of `BookingRepository` and
running the same cases — runs once with `InMemoryBookingRepository` and once
with `SqlBookingRepository` against a test database.
