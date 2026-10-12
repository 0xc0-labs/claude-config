# Examples

Implementation sketches for `SKILL.md`. TypeScript runs in a Next.js Route
Handler or a Payload custom endpoint alike: both take a Web `Request` and
return a `Response`.

## Cursor pagination (keyset)

The cursor encodes the last item's sort key and id, so the next page is
"after this row" and stays stable under inserts. Clients treat it as opaque
[Zalando 160]; signing or encrypting it is optional (no standard decides).

```ts
type Cursor = { createdAt: string; id: string };

const encode = (c: Cursor) => Buffer.from(JSON.stringify(c)).toString("base64url");
const decode = (s: string): Cursor | null => {
  try {
    return JSON.parse(Buffer.from(s, "base64url").toString("utf8"));
  } catch {
    return null;
  }
};

export async function listBookings(req: Request, repo: BookingQueries): Promise<Response> {
  const url = new URL(req.url);
  const limit = Math.min(Number(url.searchParams.get("limit") ?? 20), 100);
  const raw = url.searchParams.get("cursor");
  const after = raw ? decode(raw) : null;
  if (raw && !after) return problemJson(400, "invalid-cursor", "The cursor is not valid.");

  // One extra row tells whether a next page exists without a count query.
  const rows = await repo.list({ after, limit: limit + 1, status: url.searchParams.get("status") });
  const items = rows.slice(0, limit);
  const last = items.at(-1);

  const body: { items: typeof items; next?: string } = { items };
  if (rows.length > limit && last) {
    const next = new URL(url);
    next.searchParams.set("cursor", encode({ createdAt: last.createdAt, id: last.id }));
    body.next = next.toString();
  }
  return Response.json(body);
}
```

The query behind `repo.list` orders by `(createdAt, id)` and filters
`(createdAt, id) > (after.createdAt, after.id)`; the `id` breaks ties.

## Idempotency-Key

Per draft-ietf-httpapi-idempotency-key-header-07 (an expired Internet-Draft).
The store needs an atomic "insert if absent"; a unique index on
`(scope, key)` gives it.

```ts
type Stored =
  | { state: "in-flight"; fingerprint: string }
  | { state: "done"; fingerprint: string; status: number; headers: [string, string][]; body: string };

export interface IdempotencyStore {
  /** Returns null when the key was free and is now claimed. */
  claim(scope: string, key: string, fingerprint: string): Promise<Stored | null>;
  complete(scope: string, key: string, response: Omit<Extract<Stored, { state: "done" }>, "state">): Promise<void>;
  release(scope: string, key: string): Promise<void>;
}

export async function idempotent(
  req: Request,
  scope: string,
  store: IdempotencyStore,
  run: () => Promise<Response>,
): Promise<Response> {
  const header = req.headers.get("Idempotency-Key");
  if (!header) return problemJson(400, "idempotency-key-missing", "Idempotency-Key is required.");
  const key = header.replace(/^"|"$/g, "");

  const bodyText = await req.clone().text();
  const fingerprint = await sha256(bodyText);
  const existing = await store.claim(scope, key, fingerprint);

  if (existing) {
    if (existing.fingerprint !== fingerprint) {
      return problemJson(422, "idempotency-key-reused", "This key was used with a different request.");
    }
    if (existing.state === "in-flight") {
      return problemJson(409, "idempotency-key-in-flight", "A request with this key is still being processed.");
    }
    return new Response(existing.body, { status: existing.status, headers: existing.headers });
  }

  try {
    const res = await run();
    const body = await res.clone().text();
    await store.complete(scope, key, {
      fingerprint,
      status: res.status,
      headers: [...res.headers.entries()],
      body,
    });
    return res;
  } catch (err) {
    // A crash before completion must not lock the key until it expires.
    await store.release(scope, key);
    throw err;
  }
}

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Buffer.from(digest).toString("hex");
}
```

- `scope` is the authenticated client plus the route, so two clients cannot
  collide on a key (the draft leaves uniqueness to the resource owner).
- Error responses are stored and replayed too [draft, 2.6].
- Publish the expiry in the OpenAPI document [draft, 2.3]; 24 hours as in
  [Zalando 230] is a reasonable default.

## ETag and If-Match

```ts
async function etagOf(representation: unknown): Promise<string> {
  return `"${await sha256(JSON.stringify(representation))}"`;
}

export async function getSession(req: Request, id: string): Promise<Response> {
  const session = await sessions.find(id);
  if (!session) return problemJson(404, "not-found", "No such session.");
  const etag = await etagOf(session);
  if (req.headers.get("If-None-Match") === etag) {
    return new Response(null, { status: 304, headers: { ETag: etag } });
  }
  return Response.json(session, { headers: { ETag: etag, "Cache-Control": "private, no-cache" } });
}

export async function patchSession(req: Request, id: string): Promise<Response> {
  const current = await sessions.find(id);
  if (!current) return problemJson(404, "not-found", "No such session.");
  const ifMatch = req.headers.get("If-Match");
  if (ifMatch !== (await etagOf(current))) {
    return problemJson(412, "precondition-failed", "The session changed since you read it.");
  }
  // apply the change, return 200 with the new ETag
}
```

The equality checks are simplified: `If-None-Match` and `If-Match` may carry
a list or `*` [RFC 9110, 13.1.1–13.1.2]. A hash ETag over the representation
is what Microsoft prefers over a version counter [Microsoft]. The read and
the write in `patchSession` must be atomic with the update (a version
column in the `where` of the update), or two writers can both pass the check.

## Problem helper for a Route Handler

```ts
export function problemJson(status: number, type: string, title: string, extra: object = {}): Response {
  return new Response(JSON.stringify({ type: `/problems/${type}`, title, status, ...extra }), {
    status,
    headers: { "Content-Type": "application/problem+json" },
  });
}
```

## OpenAPI 3.1.2 fragment

```yaml
openapi: 3.1.2
info: { title: Bookings, version: 1.0.0 }
paths:
  /sessions/{id}/bookings:
    post:
      operationId: bookSeat
      parameters:
        - { name: id, in: path, required: true, schema: { type: string } }
        - name: Idempotency-Key
          in: header
          required: true
          description: Structured Field string, e.g. a UUID. Stored for 24 hours.
          schema: { type: string }
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [email]
              properties: { email: { type: string, format: email } }
      responses:
        "201":
          description: Booked.
          headers: { Location: { schema: { type: string } } }
          content: { application/json: { schema: { $ref: "#/components/schemas/Booking" } } }
        "409": { $ref: "#/components/responses/Problem" }
        "422": { $ref: "#/components/responses/Problem" }
        default: { $ref: "#/components/responses/Problem" }
components:
  responses:
    Problem:
      description: Problem details (RFC 9457).
      content:
        application/problem+json: { schema: { $ref: "#/components/schemas/Problem" } }
  schemas:
    Problem:
      type: object
      properties:
        type: { type: string, format: uri-reference }
        title: { type: string }
        status: { type: integer }
        detail: { type: string }
        instance: { type: string, format: uri-reference }
    Booking:
      type: object
      required: [id, email]
      properties: { id: { type: string }, email: { type: string } }
```
