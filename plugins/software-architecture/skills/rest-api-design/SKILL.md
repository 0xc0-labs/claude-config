---
name: rest-api-design
description: Designing and reviewing HTTP APIs — resources and URIs, method semantics (safe, idempotent), status codes, errors as application/problem+json (RFC 9457), pagination, filtering and sorting, versioning, Idempotency-Key for unsafe retries, ETags and conditional requests, OpenAPI 3.1 as the contract — and how an endpoint we write follows it while an API a framework generates is consumed as it is. Use when a session designs, implements or reviews an HTTP endpoint or an OpenAPI document.
---

# REST API design

RFCs decide what HTTP means; the Zalando and Microsoft guidelines are
conventions on top, and they sometimes disagree. Where they do, this skill
says so and picks one. Where nothing decides, it says "no standard decides
this". Source keys resolve in [references/sources.md](references/sources.md).

## First: is the API generated, or ours?

- **A generated API** (a framework's or a CMS's routes per content type, its
  query parameters, its pagination and its error body) is not ours to redesign.
  Consume it as it is, by its own documentation. A client that calls both a
  generated API and our own endpoints handles both error shapes, in one module.
- **An endpoint we write** is ours: it follows everything below.

## Resources and URIs

- Nouns, plural, kebab-case path segments: `/booking-requests/{id}`
  [Zalando 134, 129; Microsoft: kebab-case preferred].
- No verbs: an action is a resource, `POST /orders/{id}/cancellation`
  [Zalando 138]. Nest one level, for ownership: `/sessions/{id}/bookings`.
- JSON property case: **camelCase**, to match TypeScript and [Microsoft].
  Zalando requires snake_case [Zalando 118]; the guidelines still disagree,
  and the org follows its language.

## Methods

| Method | Safe | Idempotent | Use for | RFC 9110 |
|---|---|---|---|---|
| GET / HEAD | yes | yes | read | 9.3.1, 9.3.2 |
| PUT | no | yes | create or replace at a known URI | 9.3.4 |
| DELETE | no | yes | remove | 9.3.5 |
| POST | no | no | create in a collection, start a process | 9.3.3 |
| PATCH | no | no | partial update | not in RFC 9110 |

Safe: the client asks for no state change [RFC 9110, 9.2.1]. Idempotent:
repeating it has the same intended effect as sending it once, so a client may
retry it after a lost response [RFC 9110, 9.2.2]. POST and PATCH are not;
make them retryable with an Idempotency-Key (below). For a PATCH body,
use JSON Merge Patch semantics, as Microsoft does [Microsoft].

## Status codes

Use the most specific code that applies, and only common ones
[Zalando 150, 220].

| Code | When | RFC 9110 |
|---|---|---|
| 200 | success with a body | 15.3.1 |
| 201 | created; send `Location` with the new URI | 15.3.2, 10.2.2 |
| 202 | accepted, processing later | 15.3.3 |
| 204 | success, no body | 15.3.5 |
| 304 | `If-None-Match` matched; no body | 15.4.5 |
| 400 | malformed request, missing required header | 15.5.1 |
| 401 / 403 | not authenticated / authenticated but not allowed | 15.5.2, 15.5.4 |
| 404 | no such resource, **or** one in another tenant | 15.5.5 |
| 405 | method not supported; send `Allow` | 15.5.6, 10.2.1 |
| 409 | conflicts with current state (slot full, request in flight) | 15.5.10 |
| 412 | `If-Match` failed | 15.5.13 |
| 415 | body media type not accepted | 15.5.16 |
| 422 | well-formed but invalid content (validation) | 15.5.21 |
| 500 / 503 | server fault / temporarily unavailable | 15.6.1, 15.6.4 |

Answering 404 for another tenant's resource, so its existence does not leak,
is an org convention; no standard decides it.

## Errors: `application/problem+json`

Every 4xx and 5xx from our endpoints is a problem details object
[RFC 9457; Zalando 176]. Members: `type` (URI reference identifying the
problem; defaults to `about:blank`), `title`, `status`, `detail`, `instance`;
add extension members for machine-readable specifics [RFC 9457, 3.1–3.2].
`type` uses a full-path relative URI such as `/problems/slot-full`, not
meant to be dereferenced [Zalando 176]; RFC 9457 warns against relative
forms other than a full path [RFC 9457, 3.1.1].

Other guides and skills show other error bodies, `{ "error": { "code":
"...", "message": "..." } }` among the common ones. An endpoint of ours
answers with this one whatever they show: it is the standard [RFC 9457].

```http
HTTP/1.1 422 Unprocessable Content
Content-Type: application/problem+json

{
  "type": "/problems/validation",
  "title": "The request has invalid fields.",
  "status": 422,
  "detail": "2 fields are invalid.",
  "errors": [
    { "pointer": "#/email", "detail": "must be an email address" },
    { "pointer": "#/seats", "detail": "must be 1 or more" }
  ]
}
```

Clients must not depend on getting one [Zalando 176]. No stack trace or
internals in `detail` [RFC 9457, 4–5].

## Pagination, filtering, sorting

No RFC decides how a list is paged, filtered or sorted, and the guidelines
disagree. This skill sets no convention: an API uses one, the same on every
list endpoint, and its OpenAPI document describes it.

- Filters are named query parameters (`?status=open`); do not invent a query
  language.
- Document that items may shift between pages under concurrent writes
  [Microsoft].

## Versioning

No RFC decides it, and the guidelines disagree: Zalando says avoid
versioning, evolve compatibly, and if forced use media-type versioning,
never URL versioning [Zalando 113–115]; Microsoft requires an `api-version`
query parameter on every call [Microsoft]. Org convention: evolve compatibly (only
add optional fields and new resources; never rename, remove or change a
field's meaning). If a break is unavoidable, add a new resource and retire
the old one; open an issue before choosing a mechanism.

## Idempotency-Key for unsafe retries

For a POST or PATCH a client may retry (payments, bookings, emails), accept
`Idempotency-Key`, defined in **draft-ietf-httpapi-idempotency-key-header-07**,
an Internet-Draft, not an RFC, now expired [Idempotency draft]:

- Value: a Structured Field string, e.g. a UUID: `Idempotency-Key: "8e03…"`
  [draft, 2.1–2.2].
- First request: process, store the response under (key, client, endpoint)
  with a fingerprint of the body [draft, 2.4]. Retry with the same key:
  return the stored response, success or error [draft, 2.6].
- Missing key where documented as required: **400**. Same key, different
  request body: **422**. Same key while the first is still in flight: **409**.
  Each with a problem details body [draft, 2.7].
- Publish the expiry window [draft, 2.3, 2.5.2]; Zalando uses 24 hours
  [Zalando 230]. Zalando answers a changed request body with 400, the draft
  with 422; follow the draft. Microsoft uses `Repeatability-Request-ID` instead
  [Microsoft].

## ETags and conditional requests

- Send `ETag` on GET of a single resource [RFC 9110, 8.8.3; Zalando 182].
- Reads: `If-None-Match` → 304 when unchanged [RFC 9110, 13.1.2; 15.4.5].
- Writes: require `If-Match` on PUT/PATCH/DELETE where lost updates matter;
  mismatch → 412 [RFC 9110, 13.1.1; 15.5.13]. `If-None-Match: *` on a PUT
  that must only create [RFC 9110, 13.1.2; Zalando 182].
- Cache: `Cache-Control: private` or `no-store` for anything per user or
  per tenant behind auth [RFC 9111, 5.2.2.5, 5.2.2.7]; `max-age` plus an
  ETag for public reads [RFC 9111, 5.2.2.1, 4.3].

## OpenAPI 3.1 as the contract

- Write the OpenAPI document first and review it in the PR before the code
  [Zalando 100, 101, 192]. Target **OpenAPI 3.1.2** [OpenAPI 3.1.2]; its
  Schema Object is JSON Schema 2020-12.
- Document every success response and every service-specific error, with the
  problem schema; standard errors may share a `default` response
  [Zalando 151].
- Where the file lives and how it is linted is per repo (no standard decides
  this). Example: [references/examples.md](references/examples.md).

## An endpoint inside a framework

A custom endpoint may **not be authenticated** even where the generated routes
are, and may get no parsed body and no CORS headers: check, for the framework in
use, what a custom endpoint must do itself. A framework's in-process data API
may skip the access control its HTTP API applies: pass it the caller and ask for
the access rules explicitly.

## Anti-patterns

- Verbs in paths; a `GET` that changes state; `POST` for everything.
- `200` with `{ "success": false }`; a bare string as error body.
- Two list endpoints of one API that page or sort differently.
- A version segment in the URL "just in case"; a retryable POST without
  an Idempotency-Key; an endpoint whose OpenAPI document is stale.
- Redesigning a generated API instead of adding an endpoint of our own.

## Review checklist

- [ ] Plural kebab-case nouns, no verbs, nesting at most one level.
- [ ] Each method used per its semantics; status codes from the table.
- [ ] Every error is `application/problem+json`; no internals leaked.
- [ ] Lists: one pagination and sorting convention across the API, in its
      OpenAPI document; filters as named params.
- [ ] Retryable POST/PATCH accept `Idempotency-Key` with 400/409/422.
- [ ] `ETag` on reads; `If-Match` → 412 where lost updates matter.
- [ ] A custom endpoint inside a framework authenticates the caller and
      checks the tenant itself.
- [ ] OpenAPI 3.1.2 document updated in the same PR.

## Sources

[references/sources.md](references/sources.md): RFC 9110, 9111, 9457;
draft-ietf-httpapi-idempotency-key-header-07; OpenAPI 3.1.2; Zalando and
Microsoft Azure guidelines.
