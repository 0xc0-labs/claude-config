# Context map patterns

How two bounded contexts relate. Name the pattern for every pair that talks;
an unnamed relationship is usually an accidental conformist. Upstream (U)
is the side whose changes the other must absorb; downstream (D) absorbs them.

| Pattern | What it means | Pick it when | Source |
|---|---|---|---|
| Partnership | Two teams succeed or fail together and plan changes jointly | Both sides change in lockstep and the same people own both | [Vernon 2013, ch. 3] |
| Shared Kernel | A small part of the model is shared and changed only by agreement | Two contexts truly need identical code; keep it tiny | [Evans 2003, ch. 14] |
| Customer/Supplier | Downstream's needs feed upstream's planning | Upstream is willing to serve downstream | [Evans 2003, ch. 14] |
| Conformist | Downstream adopts upstream's model as is | Upstream will not adapt and its model is good enough | [Evans 2003, ch. 14] |
| Anticorruption Layer | Downstream translates upstream's model into its own | Upstream's model would distort downstream's language | [Evans 2003, ch. 14] |
| Open Host Service | Upstream offers a defined protocol for all consumers | Many consumers; one integration instead of one per consumer | [Evans 2003, ch. 14] |
| Published Language | A documented exchange format | Pairs with Open Host Service; an OpenAPI document is one | [Evans 2003, ch. 14] |
| Separate Ways | No integration at all | Integration costs more than it returns | [Evans 2003, ch. 14] |

Vernon also discusses integrating contexts over REST and messaging
[Vernon 2013, ch. 13] and draws context maps as a planning tool
[Vernon 2016, ch. 4].

## In this org

Org convention; no source decides these:

- **A backend → each front that reads it.** A backend that publishes one API
  for all its fronts is an Open Host Service. A front that only displays
  content conforms. A front with its own vocabulary keeps a mapping module
  (its anticorruption layer) that turns the backend's documents into its own
  types; components never see the backend's generated types.
- **Shared code across repos** is a versioned package in
  `0xc0-labs/packages` (workspace `CLAUDE.md`). A package that carries a
  domain model is a Shared Kernel: keep it small, change it by agreement,
  and prefer copying a value object over sharing an aggregate.
- **Third-party APIs** (payments, email, analytics) are upstream with no
  customer relationship: always an anticorruption layer, so their names do
  not reach the domain.

## Drawing one

A context map can be a Markdown table in the repo's `docs/`:

```text
| Upstream | Downstream | Pattern | Contract |
|---|---|---|---|
| cms (content) | shop front | OHS + Published Language / Conformist | the CMS's REST API, generated types |
| cms (bookings) | shop front | OHS / ACL | openapi.yaml, bookings/mapping.ts |
| payment provider | cms (bookings) | ACL | payments/payment-adapter.ts |
```

The rows above are illustrative, not the org's current map.
