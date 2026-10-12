# Payload's REST API and custom endpoints

Checked on 2026-10-12 against Payload's documentation at payloadcms.com/docs,
which documents the 3.x line; the latest stable release then was **v3.90.2**
(2026-09-23). The `main` branch already carries `4.0.0-beta.0`: re-check
this page when the repos move to 4.x. Links in [sources.md](sources.md).

## What Payload decides for us

Not ours to change; the front consumes it as documented [Payload REST].

| Topic | Payload's behaviour |
|---|---|
| Base path | `routes.api`, default `/api` |
| Collection routes | `GET /api/{slug}`, `GET /api/{slug}/{id}`, `GET /api/{slug}/count`, `POST /api/{slug}`, `PATCH /api/{slug}` (bulk, by `where`), `PATCH /api/{slug}/{id}`, `DELETE /api/{slug}` (bulk), `DELETE /api/{slug}/{id}` |
| Slugs | kebab-case |
| Globals | `GET` and `POST /api/globals/{slug}`; no create, no delete |
| Auth routes | on auth collections: `POST /login`, `/logout`, `/refresh-token`, `/forgot-password`, `/reset-password`, `/unlock`, `/verify/{token}`; `GET /me` |
| Query parameters | `depth`, `locale`, `fallback-locale`, `select`, `populate`, `limit`, `page`, `sort`, `where`, `joins` |
| Filtering | `where[field][operator]=value`: `equals`, `not_equals`, `greater_than`, `greater_than_equal`, `less_than`, `less_than_equal`, `like`, `contains`, `in`, `not_in`, `exists`, `all` (MongoDB only), geo operators; `and`/`or` nest [Payload queries] |
| Sorting | `sort=-createdAt`, comma-separated for several fields [Payload sort] |
| Pagination | page numbers, not cursors. `limit` defaults to 10, `page` to 1; `limit=0` returns everything. Response: `docs`, `totalDocs`, `limit`, `totalPages`, `page`, `pagingCounter`, `hasPrevPage`, `hasNextPage`, `prevPage`, `nextPage` [Payload pagination] |
| Long queries | `POST` with `X-Payload-HTTP-Method-Override: GET` and the query in the body |
| Errors | `application/json` body `{ "errors": [ { "message": "...", "name"?, "data"? } ] }`, status from the error, 500 by default; non-public errors replaced by a generic message [Payload source] |

Consequences:

- Payload's errors are **not** RFC 9457 problem details. A front that calls
  both Payload's routes and our custom ones handles both shapes, in one
  client module.
- Payload's lists are page-based. Fine for admin-sized collections; a
  custom endpoint with a cursor where a list grows without bound.
- The pages checked do not document `ETag`, conditional requests or
  `Idempotency-Key` on Payload's generated routes. Do not rely on them there
  without checking the version in use.
- Build `where` query strings with `qs-esm`'s `stringify`, as the docs do
  [Payload queries].

## What a custom endpoint must do itself

From the docs [Payload REST]:

- Declared in `endpoints` on the config, a collection or a global: `path`
  (appended after the slug), lowercase `method`, `handler(req)` returning a
  `Response`.
- **Not authenticated by default**: check `req.user` yourself.
- `req.data` is not populated: `await req.json()`, or
  `addDataAndFileToRequest(req)`.
- Locale is not set: `addLocalesToRequestFromData(req)` when it matters.
- No CORS headers unless you add them: `headersWithCors({ headers, req })`.
- Path parameters arrive in `req.routeParams`.
- Mounted under `routes.api`; a route outside it is a Next.js Route Handler.

Local API calls default to `overrideAccess: true`, skipping access control
[Payload Local API]. Pass `overrideAccess: false` and `user: req.user` so
collection access rules, the multi-tenant plugin's included, apply to the
caller [Payload Local API; Payload multi-tenant].

## Example: an endpoint that follows the skill

`POST /api/sessions/:id/bookings`, retryable, problem details, tenant-scoped.

```ts
// src/collections/sessions/endpoints.ts
import type { CollectionConfig, PayloadRequest } from "payload";
import { headersWithCors } from "payload";
import { problem } from "@/http/problem";
import { idempotent } from "@/http/idempotency";
import { idempotencyStore } from "@/http/idempotency-store";
import { bookSeat } from "@/bookings/application/book-seat";

export const sessionEndpoints: CollectionConfig["endpoints"] = [
  {
    path: "/:id/bookings",
    method: "post",
    handler: async (req: PayloadRequest) => {
      const user = req.user;
      if (!user) return problem(req, 401, "unauthenticated", "Log in first.");

      return idempotent(req, `user:${user.id}:book-seat`, idempotencyStore(req.payload), async () => {
        const id = String(req.routeParams?.id ?? "");
        const session = await req.payload
          .findByID({ collection: "sessions", id, overrideAccess: false, user })
          .catch(() => null);
        // 404 also for another tenant's session: its existence must not leak.
        if (!session) return problem(req, 404, "not-found", "No such session.");

        const body = await req.json().catch(() => null);
        if (typeof body?.email !== "string") {
          return problem(req, 422, "validation", "The request has invalid fields.", {
            errors: [{ pointer: "#/email", detail: "is required" }],
          });
        }

        const result = await bookSeat(req.payload, session, body.email);
        if (!result.ok) return problem(req, 409, "slot-full", "The session is full.");

        return Response.json(result.booking, {
          status: 201,
          headers: headersWithCors({
            headers: new Headers({ Location: `/api/bookings/${result.booking.id}` }),
            req,
          }),
        });
      });
    },
  },
];
```

```ts
// src/http/problem.ts
import type { PayloadRequest } from "payload";
import { headersWithCors } from "payload";

export function problem(
  req: PayloadRequest,
  status: number,
  type: string,
  title: string,
  extra: Record<string, unknown> = {},
): Response {
  return new Response(JSON.stringify({ type: `/problems/${type}`, title, status, ...extra }), {
    status,
    headers: headersWithCors({
      headers: new Headers({ "Content-Type": "application/problem+json" }),
      req,
    }),
  });
}
```

`idempotent` is in [examples.md](examples.md); `idempotencyStore` implements
its `IdempotencyStore` over a collection with a unique index on
`(scope, key)`. The handler maps HTTP
to a use case and back; the rule "the session is full" lives in the domain
(skills `hexagonal-architecture` and `domain-driven-design`).
