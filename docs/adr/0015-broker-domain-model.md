# 0015. Broker domain model

- Status: accepted
- Date: 2026-05-16
- Deciders: @emacsway

## Definition of model

> "every model represents some aspect of reality or an idea that
> is of interest. A model is a simplification. It is an
> interpretation of reality that abstracts the aspects relevant
> to solving the problem at hand and ignores extraneous detail..."
>
> -- "Domain-Driven Design: Tackling Complexity in the Heart of
> Software" by Eric Evans

A model is **an abstraction** — selective omission of detail
irrelevant to the problem at hand.

A model has a **subject** (who models) and an **object** (what
is modeled). The object exists independently of the model and is
not the model's own output.

## What `broker.Order` models

`broker.Order` models **the function broker BC executes** —
routing orders to a venue, observing their state, propagating
that state into our system.

- Subject: broker BC.
- Object: the activity of order routing.

`Order.t`, `kind`, `tif`, `status`, the arithmetic on `quantity`
/ `filled` / `remaining`, the `is_terminal` / `is_active`
partition — these are the vocabulary and invariants of that
activity. They define what broker BC means when it speaks about
an order.

`paper_broker.Order` models a different function — matching as
a venue — and is therefore a different model under the same
name. Both are valid.

## What `broker.Order` does not model

- **Not** "an order at the venue". The venue owns the order; we
  do not. Modeling someone else's scope through our types is a
  scope violation.
- **Not** "our Published Language". The Published Language is
  itself a model — the formal vocabulary broker BC publishes for
  sibling integration. It is an output of `broker.Order`, not
  its object. A model does not model its own projection.

## Abstraction over heterogeneous concrete brokers

Concrete venues (BCS, Finam, Synthetic, future ones) differ in
protocol detail: client-order-id format, status enums, whether
the venue accepts caller-supplied ids. These differences are
**irrelevant to the function broker BC executes** — order
routing is the same activity regardless of which venue receives
the route.

`broker.Order` is the single common form spoken inside the BC.
Venue-specific shapes live strictly below the ACL boundary.

## Role of ACL

ACL's job is to **defend this abstraction**. Each ACL adapter
translates a concrete venue's specifics in (venue response →
`broker.Order`) and out (broker's instructions → venue protocol).
Venue specifics never leak into the domain. The abstraction
stays uncorrupted — which is the original meaning of
*Anti-Corruption Layer*.
