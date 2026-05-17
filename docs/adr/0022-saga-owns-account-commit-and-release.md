# 0022. Order_process_manager owns Account commit and release

- Status: accepted
- Date: 2026-05-17
- Deciders: @emacsway

## Context

Before this ADR, Account had two parallel paths into its
reservation ledger:

1. **The Reserve / Release path.** Order_management's saga
   dispatched `Reserve_command` at start and (until step 3) EM
   itself dispatched `Release_command` directly on each ticket's
   terminal failed / cancelled event. So EM, with no business
   stake in Account's ledger, was sending Account a wire command.

2. **The broker-IE path.** Account subscribed to three of
   broker's outbound IEs — `Order_filled`, `Order_rejected`,
   `Order_unreachable` — and translated each into a
   Commit_fill / Release on the same reservation. This is the
   model from when the saga was a single-step intent → submit
   pipeline (one reservation backs one broker order) and the
   conflation of `placement_id` with `reservation_id` held.

After ADR 0017 introduced the OrderTicket aggregate (one ticket
fans out into N broker placements) and ADR 0020 extracted the
saga into `order_management`, both paths broke in spirit:

- **`placement_id ≠ reservation_id`.** EM encodes the wire
  placement_id as `ticket_id * 1_000_000 + local_seq` for global
  uniqueness across all tickets' placements. Account decoding
  `placement_id` as `reservation_id` would look up the wrong
  reservation (or fail outright once a real TWAP runs).

- **Per-placement IE doesn't compose at ticket level.** A
  TWAP with 50 slices generates 50 broker `Order_filled` IEs for
  one reservation. Account, subscribing to each as a separate
  Commit_fill, has no way to reason about the aggregate. The
  reasoning lives at the ticket level — i.e. inside the
  OrderTicket aggregate.

- **EM doesn't own Account's vocabulary.** EM's job is execution
  (slicing, broker dialog). Dispatching Release_command to
  Account is policy that doesn't belong in the EMS layer.

- **Bidirectional awareness.** EM dispatching commands to
  Account and Account subscribing to broker IEs (a different
  BC) means three BCs participate in Account's reservation
  lifecycle. Reasoning about correctness gets harder for each
  added participant.

## Decision

Make `Order_management.Order_process_manager` the **single
owner** of Account-side reservation orchestration:

- Saga state machine extends with a Working state and four new
  events (`Ticket_fill_recorded`, `Ticket_completed`,
  `Ticket_cancelled`, `Ticket_failed`) consumed from EM's
  outbound IEs.
- Saga dispatches `Commit_fill_command` to Account on every
  per-fill IE.
- Saga dispatches `Release_command` to Account on terminal
  Ticket_cancelled / Ticket_failed.
- Saga reaches `Settled` (no command) on `Ticket_completed` —
  the per-fill commits have already drawn the reservation down
  to zero.
- EM stops publishing `Release_command` directly. EM no longer
  imports any Account-side wire shape.
- Account stops subscribing to broker IEs. All Account ACL
  handlers for `Order_filled` / `Order_rejected` /
  `Order_unreachable` / `Order_accepted` are removed; their
  atdgen mirrors removed from the dune.

### New EM outbound IE: Order_ticket_fill_recorded

To close the per-fill semantic gap, EM publishes a new IE on
every `Ev_placement_filled` domain event:

```
order_ticket_fill_recorded_integration_event {
  correlation_id   : string;  (saga routing key)
  ticket_id        : int;     (EMS aggregate identity)
  reservation_id   : int;     (Account identity)
  fill_quantity    : string;
  fill_price       : string;
  fee              : string;
  occurred_at      : iso8601;
}
```

The wire carries both `ticket_id` (for audit / analytics /
operator UI) and `reservation_id` (the Account-relevant key the
saga uses for `Commit_fill_command`).

### Explicit Reservation_id on the aggregate

The OrderTicket aggregate gains a `Reservation_id` VO field
distinct from its `Ticket_id`. Today the application layer
constructs them with the same numeric value (one reservation
backs one ticket) — but the types are separate so a future
one-to-many or different-id-space model lands without
refactoring the aggregate. Every aggregate event that crosses
the BC boundary (`Ticket_opened`, `Ticket_completed`,
`Ticket_cancelled`, `Ticket_failed`, plus the new
`Placement_filled` IE wire shape) carries `reservation_id` so
consumers don't reach across the aggregate's identity-space
boundary.

### Per-fill: fire-and-forget vs request/response

The saga emits `Commit_fill_command` on every
`Ticket_fill_recorded` and does NOT wait for an Account-side
acknowledgement before moving to the next fill. Fire-and-forget.

The invariant this assumes: **Commit_fill_command is idempotent
at Account** (re-applying a fill that's already been recorded
is a no-op). The in-memory bus delivers at-least-once and the
saga state machine itself doesn't deduplicate fills. With
durable persistence and explicit deduplication, this assumption
holds for free; the in-memory model relies on the fact that
each `Ticket_fill_recorded` IE corresponds to one
`Ev_placement_filled` which the aggregate's terminal-absorption
invariant guarantees fires at most once per fill.

Request/response per-fill (saga tracks `fills_pending`, waits
for `Reservation_filled` IE) is plausible if backpressure or
recovery semantics ever require it; the upgrade leaves the
wire commands untouched.

### Settled vs Released

The saga's two terminal flavours match the two ways a ticket
finishes:

| Saga terminal     | Triggering IE                  | Command emitted          |
|-------------------|--------------------------------|--------------------------|
| Settled           | Ticket_completed               | none — fills did it all  |
| Released          | Ticket_cancelled / _failed     | Release_command          |
| Compensated       | Reservation_rejected           | none — never reserved    |

Settled is conceptually "all the cash has been drawn down by
per-fill commits; there's nothing left to release"; Released is
"the ticket terminated with unfilled remainder, release the
unused portion at Account".

This relies on Account's `Commit_fill_command` accepting fees
on top of the price × quantity draw; the Reservation's
`reserved_cash` covers the cash earmark plus a slippage / fee
buffer, and the residual buffer is what Release frees when the
ticket fails.

## Consequences

**Easier:**

- Account has one direction of cross-BC traffic: it receives
  three command topics from order_management and emits three IE
  topics back. No broker dependency. Audit reasoning is
  proportional to one BC's contract.
- The saga is the single source of truth for "what does Account
  owe this reservation right now". Trip points are obvious.
- The `placement_id ≠ reservation_id` confusion is structurally
  prevented — Account never sees `placement_id`.
- TWAP / VWAP / Iceberg work end-to-end without an artificial
  one-fill-per-reservation assumption.

**Harder:**

- The saga state space grows from 3 states (Awaiting / Done /
  Compensated) to 5 (Awaiting / Working / Settled / Released /
  Compensated). Workflow_engine handles persistence naturally;
  the additional states are well-scoped.
- Per-fill commit is fire-and-forget; the saga doesn't observe
  Account-side commit failures. Acceptable today (Account's
  in-memory ledger is reliable); under durable persistence it
  becomes a real invariant to defend (idempotent commit, or
  request/response upgrade).
- EM's outbound IE surface grows by one (the fill_recorded IE).
  Telemetry / analytics consumers gain access to per-fill data
  through this shape rather than peeking at broker's order-filled
  directly.

**To watch for:**

- The fire-and-forget per-fill commit is correct only if every
  `Ticket_fill_recorded` IE has a corresponding `Ev_placement_filled`
  at most once. The aggregate's terminal-absorption invariant
  guarantees this in-domain. If the bus introduces deduplication
  failures (network split, replay) the saga would need an
  explicit dedup key — likely a (correlation_id, ticket_id,
  occurred_at) tuple.
- A future operator-initiated cancel scenario would surface a
  partial-fill-then-cancel sequence. The saga handles this
  naturally today: each per-fill Commit_fill draws the
  reservation down, then the terminal `Ticket_cancelled`
  Release_command frees the remaining buffer.

## References

- ADR 0017 — OrderTicket aggregate + OMS / EMS layering inside
  execution_management (the placement-fanout that broke the
  one-reservation-one-broker-order assumption).
- ADR 0020 — Order_management as a separate Bounded Context
  (the saga extraction that this ADR builds on).
- ADR 0005 — Reservations ledger (Account's internal model;
  Commit_fill_command and Release_command are its existing
  imperative surface).
