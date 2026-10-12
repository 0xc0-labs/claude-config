# Worked example: a session aggregate stored in Payload

A small bookings context for an artist's site. The operator's words are
"session", "seat", "book", "cancel", "waitlist"; the code uses them. Names
are illustrative.

## Value objects

```ts
// bookings/domain/values.ts
export class DomainError extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}

export class Email {
  private constructor(readonly value: string) {}
  static parse(raw: string): Email {
    const v = raw.trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+$/.test(v)) throw new DomainError("email.invalid");
    return new Email(v);
  }
}

declare const brand: unique symbol;
export type SessionId = string & { readonly [brand]: "SessionId" };
export type TenantId = string & { readonly [brand]: "TenantId" };

export class Capacity {
  private constructor(readonly seats: number) {}
  static of(seats: number): Capacity {
    if (!Number.isInteger(seats) || seats < 1) throw new DomainError("capacity.invalid");
    return new Capacity(seats);
  }
}
```

Branded ids stop a `TenantId` being passed where a `SessionId` is expected,
at no runtime cost.

## The aggregate

Invariants owned by `Session`:

1. Booked seats never exceed capacity.
2. An email books a session at most once.
3. A cancelled session takes no bookings.

```ts
// bookings/domain/session.ts
import { Capacity, DomainError, Email, type SessionId, type TenantId } from "./values";

export type SessionEvent =
  | { type: "SessionBooked"; sessionId: SessionId; email: string }
  | { type: "BookingCancelled"; sessionId: SessionId; email: string }
  | { type: "SessionCancelled"; sessionId: SessionId; attendees: string[] };

type State = {
  id: SessionId;
  tenantId: TenantId;
  capacity: Capacity;
  attendees: string[];
  cancelled: boolean;
  version: number;
};

export class Session {
  private events: SessionEvent[] = [];
  private constructor(private state: State) {}

  static schedule(id: SessionId, tenantId: TenantId, capacity: Capacity): Session {
    return new Session({ id, tenantId, capacity, attendees: [], cancelled: false, version: 0 });
  }

  /** Rebuilds from storage; checks nothing, since stored state was valid when saved. */
  static restore(state: State): Session {
    return new Session(state);
  }

  get id() { return this.state.id; }
  get tenantId() { return this.state.tenantId; }
  get version() { return this.state.version; }
  get seatsLeft() { return this.state.capacity.seats - this.state.attendees.length; }

  book(email: Email): void {
    if (this.state.cancelled) throw new DomainError("session.cancelled");
    if (this.state.attendees.includes(email.value)) throw new DomainError("session.already-booked");
    if (this.seatsLeft <= 0) throw new DomainError("session.full");
    this.state.attendees.push(email.value);
    this.events.push({ type: "SessionBooked", sessionId: this.id, email: email.value });
  }

  cancelBooking(email: Email): void {
    const before = this.state.attendees.length;
    this.state.attendees = this.state.attendees.filter((a) => a !== email.value);
    if (this.state.attendees.length === before) throw new DomainError("session.not-booked");
    this.events.push({ type: "BookingCancelled", sessionId: this.id, email: email.value });
  }

  cancel(): void {
    if (this.state.cancelled) return;
    this.state.cancelled = true;
    this.events.push({
      type: "SessionCancelled",
      sessionId: this.id,
      attendees: [...this.state.attendees],
    });
  }

  snapshot(): Readonly<State> {
    return { ...this.state, attendees: [...this.state.attendees] };
  }

  pullEvents(): SessionEvent[] {
    const out = this.events;
    this.events = [];
    return out;
  }
}
```

The waitlist is a separate aggregate that reacts to `BookingCancelled`: it
is not needed to keep any of the three invariants, so it stays outside
[Vernon 2013, ch. 10].

## Repository port and Payload adapter

```ts
// bookings/domain/session-repository.ts
export interface SessionRepository {
  get(tenantId: TenantId, id: SessionId): Promise<Session | null>;
  /** Fails with ConcurrencyError if the stored version moved since it was read. */
  save(session: Session): Promise<void>;
}
```

```ts
// bookings/adapters/payload-session-repository.ts
import type { Payload } from "payload";

export class PayloadSessionRepository implements SessionRepository {
  constructor(private readonly payload: Payload) {}

  async get(tenantId: TenantId, id: SessionId): Promise<Session | null> {
    const { docs } = await this.payload.find({
      collection: "sessions",
      where: { and: [{ id: { equals: id } }, { tenant: { equals: tenantId } }] },
      limit: 1,
    });
    const doc = docs.at(0);
    if (!doc) return null;
    return Session.restore({
      id,
      tenantId,
      capacity: Capacity.of(doc.capacity),
      attendees: (doc.attendees ?? []).map((a) => a.email),
      cancelled: Boolean(doc.cancelled),
      version: doc.version ?? 0,
    });
  }

  async save(session: Session): Promise<void> {
    const s = session.snapshot();
    const { docs } = await this.payload.update({
      collection: "sessions",
      where: {
        and: [{ id: { equals: s.id } }, { tenant: { equals: s.tenantId } }, { version: { equals: s.version } }],
      },
      data: {
        capacity: s.capacity.seats,
        attendees: s.attendees.map((email) => ({ email })),
        cancelled: s.cancelled,
        version: s.version + 1,
      },
    });
    if (docs.length === 0) throw new ConcurrencyError(s.id);
  }
}
```

The `version` field gives optimistic concurrency: two requests that both read
version 3 cannot both write. Whether a filtered update is atomic depends on
the database adapter Payload runs on; confirm it for the adapter in use.

## Application service

```ts
export async function bookSeat(
  deps: { sessions: SessionRepository; publish: (e: SessionEvent[]) => Promise<void> },
  cmd: { tenantId: TenantId; sessionId: SessionId; email: string },
): Promise<void> {
  const session = await deps.sessions.get(cmd.tenantId, cmd.sessionId);
  if (!session) throw new DomainError("session.not-found");
  session.book(Email.parse(cmd.email));
  await deps.sessions.save(session);
  await deps.publish(session.pullEvents());
}
```

One aggregate loaded, changed and saved; events leave only after the save
succeeds [Vernon 2013, ch. 8 and 10]. If publishing must never be lost,
store events with the aggregate in the same write and relay them later; no
source in this skill's list prescribes that mechanism.

## Tests

```ts
import { expect, it } from "vitest";

it("never books past capacity", () => {
  const s = Session.schedule("s1" as SessionId, "t1" as TenantId, Capacity.of(1));
  s.book(Email.parse("a@x.io"));
  expect(() => s.book(Email.parse("b@x.io"))).toThrow("session.full");
});

it("emits one event per booking", () => {
  const s = Session.schedule("s1" as SessionId, "t1" as TenantId, Capacity.of(2));
  s.book(Email.parse("a@x.io"));
  expect(s.pullEvents()).toEqual([{ type: "SessionBooked", sessionId: "s1", email: "a@x.io" }]);
  expect(s.pullEvents()).toEqual([]);
});
```

Aggregate tests need no repository, no Payload and no Next.js.
