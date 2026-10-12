---
name: domain-driven-design
description: Domain-Driven Design for TypeScript application code — strategic (bounded contexts, ubiquitous language, context maps) and tactical (entities, value objects, aggregates and their invariants, domain events, repositories), how it maps onto Payload collections and Next.js fronts, and when it is overkill. Use when a session models business rules, splits a system into contexts, names domain concepts, designs or reviews an aggregate, or decides whether DDD is worth it for a repo.
---

# Domain-Driven Design

Model the business in code, in the business's own words, and draw explicit
lines where those words change meaning [Evans 2003, ch. 2 and 14]. Source
keys in brackets resolve in [references/sources.md](references/sources.md).

## Decide first

| Situation | Do |
|---|---|
| Content site: pages, posts, media, menus edited in Payload | **No DDD.** Payload collections are the model. |
| CRUD with validation and access rules | **No tactical DDD.** A shared vocabulary still helps. |
| Rules that interact and must always hold (stock, bookings, pricing, entitlements, a workflow with states) | **Tactical DDD** for that part. |
| Several teams, fronts or tenants where one word means different things | **Strategic DDD**: name the contexts and map them. |

Evans aims DDD at complex domains and says to spend the effort on the core
domain, not on generic or supporting parts [Evans 2003, ch. 15; Vernon 2016,
ch. 3]. No source gives a size threshold; the table is a judgment.

## Strategic design

- **Ubiquitous language.** One vocabulary shared by the people who know the
  business and the code: type names, function names, events, UI copy, issue
  titles. When a conversation needs a new word, the code gets it too; when a
  code name would confuse the operator, rename it [Evans 2003, ch. 2].
- **Bounded context.** The boundary inside which one model and its language
  hold without contradiction. Outside it, the same word may mean something
  else and that is fine [Evans 2003, ch. 14; Vernon 2013, ch. 2].
- **Subdomains.** Core (why the business exists, worth the modelling),
  supporting (needed, specific, simpler), generic (buy or use off the shelf)
  [Evans 2003, ch. 15; Vernon 2016, ch. 3].
- **Context map.** The explicit list of contexts and how each pair relates.
  Patterns and when to pick each: [references/context-maps.md](references/context-maps.md)
  [Evans 2003, ch. 14; Vernon 2013, ch. 3].

In this org (org convention; no source decides this):

- Content (pages, media, navigation) is a generic subdomain: Payload solves
  it; do not model it.
- A front's own business (an artist's bookings, a shop's orders) is its own
  context, even when its data is stored through Payload.
- The tenant is a boundary of data, not a bounded context: two tenants
  sharing the same rules share one model.
- A Next.js front reading Payload's REST API is a downstream **conformist**
  to Payload's model; put an **anticorruption layer** (a mapping module)
  between them as soon as the front's own words differ from Payload's.

## Tactical design: the building blocks

| Block | Identity | Mutable | Equality | In TypeScript |
|---|---|---|---|---|
| Value object | none | no | by value | `readonly` fields, a factory that validates, methods return new values |
| Entity | yes, stable for its life | yes, through methods | by id | class with a private constructor and intention-revealing methods |
| Aggregate | its root's id | only through the root | by id | the root entity plus what must change with it |
| Domain event | none (an event id for transport) | no | — | a plain readonly object, past-tense name |
| Repository | — | — | — | an interface per aggregate, returning whole aggregates |

[Evans 2003, ch. 5–6; Vernon 2013, ch. 5, 6, 8, 10, 12]

### Value objects first

Prefer a value object whenever identity does not matter: money, an email, a
date range, a slug, a capacity. It makes invalid states unrepresentable and
removes defensive checks elsewhere [Evans 2003, ch. 5; Vernon 2013, ch. 6].

```ts
export class Money {
  private constructor(readonly cents: number, readonly currency: "EUR" | "USD") {}

  static of(cents: number, currency: Money["currency"]): Money {
    if (!Number.isInteger(cents) || cents < 0) throw new DomainError("money.invalid");
    return new Money(cents, currency);
  }
  add(other: Money): Money {
    if (other.currency !== this.currency) throw new DomainError("money.currency-mismatch");
    return new Money(this.cents + other.cents, this.currency);
  }
  equals(other: Money): boolean {
    return this.cents === other.cents && this.currency === other.currency;
  }
}
```

### Aggregates and invariants

An aggregate is a consistency boundary: everything inside it is consistent
when a transaction commits [Evans 2003, ch. 6]. Vernon's rules
[Vernon 2013, ch. 10; Vernon 2016, ch. 5]:

1. Put inside only what a **true invariant** needs to change together.
2. Keep aggregates **small**; default to the root and its value objects.
3. Reference other aggregates **by id**, never by object.
4. Change **one aggregate per transaction**; reach others through domain
   events and eventual consistency.

```ts
export class Session {
  private readonly attendees = new Set<string>();
  private readonly pending: DomainEvent[] = [];

  private constructor(readonly id: SessionId, private readonly capacity: number) {}

  book(email: Email): void {
    if (this.attendees.has(email.value)) throw new DomainError("session.already-booked");
    if (this.attendees.size >= this.capacity) throw new DomainError("session.full");
    this.attendees.add(email.value);
    this.pending.push({ type: "SessionBooked", sessionId: this.id.value, email: email.value });
  }

  pullEvents(): DomainEvent[] {
    return this.pending.splice(0);
  }
}
```

The invariant "never over capacity" lives in the method that could break it,
so no caller can skip it. Fuller model, repository and mapping to Payload:
[references/example.md](references/example.md).

### Domain events

Something that happened that the business cares about, named in the past
tense in the ubiquitous language (`SessionBooked`, not `BookingCreated` if
the business says "booked") [Vernon 2013, ch. 8; Vernon 2016, ch. 6].
Raised by the aggregate, published after the transaction commits, consumed
by other aggregates or contexts. Evans's 2003 book does not include them as a
building block; Vernon does.

### Repositories

One per aggregate root, with a collection-like interface in the domain's
terms; the implementation is an adapter [Evans 2003, ch. 6; Vernon 2013,
ch. 12]. Over Payload: the repository maps a Payload document to the
aggregate and back, and is the only code that knows the collection's slug.
See the `hexagonal-architecture` skill for ports and adapters.

## Payload and Next.js specifics

These apply the sources above to this stack (org convention).

- A Payload collection is a persistence and admin schema. It may store an
  aggregate; it is not the aggregate. Its generated types stay in adapters.
- Enforce aggregate invariants where every write passes: the domain method,
  called from a Payload hook so admin edits and REST writes obey it too.
- Events must reach other contexts only once the write has succeeded
  [Vernon 2013, ch. 8]. Pull them from the aggregate after the repository's
  save returns, not from a hook that may fire before the write is final
  (the mechanism is an org convention; no source decides it).
- Fronts read for display; they do not need aggregates. Query Payload
  directly for read models.

## Anti-patterns

- **Anemic model:** classes with public setters and all rules in services
  [Vernon 2013, ch. 1 and 7].
- **Raw primitives for concepts:** `string` for email, slug, money, tenant
  id, so every caller re-validates [Vernon 2013, ch. 6].
- **Large aggregate:** a `Tenant` holding every page, booking and user
  [Vernon 2013, ch. 10].
- **Object references across aggregates:** `order.customer.address` loaded
  and changed in one transaction [Vernon 2013, ch. 10].
- **Generic repository:** `Repository<T>.find(where)` leaking a query
  language into the domain; a repository speaks its aggregate's terms
  [Evans 2003, ch. 6].
- **One model for everything:** the admin's "product" and the shop's
  "product" forced into one type across contexts [Evans 2003, ch. 14].
- **DDD vocabulary without DDD:** folders named `aggregates/` around CRUD
  (judgment; see "Decide first").

## Review checklist

- [ ] The decision table justifies the depth of modelling used.
- [ ] Names match the words the operator uses; a glossary exists if a term
      is ambiguous.
- [ ] Each context is named; each relationship between contexts is a named
      pattern.
- [ ] Every invariant is enforced inside one aggregate method.
- [ ] Aggregates reference each other by id; one aggregate per transaction.
- [ ] Value objects are immutable and validated on creation.
- [ ] Repositories exist only for aggregate roots and return whole
      aggregates.
- [ ] No Payload or Next.js import under the domain folder.
- [ ] Events are past tense, immutable, and dispatched after commit.

## Sources

Full list with editions and links: [references/sources.md](references/sources.md).
Evans, "Domain-Driven Design" (2003); Vernon, "Implementing Domain-Driven
Design" (2013) and "Domain-Driven Design Distilled" (2016).
