# Functional hexagonal

This document covers the *application layer* structure: how
commands, events, workflows and DTO projections fit into the
hexagonal skeleton from [`overview.md`](overview.md).

The base hexagonal rules (domain at the center, application
orchestrating, infrastructure at the edges) still apply. What's
added here is a functional-programming flavor of the same
pattern, in the spirit of Scott Wlaschin's *Domain Modeling Made
Functional*: pure pipelines, typed events, accumulating
validation, no mutable aggregates.

## Layered picture

```
┌──────────────────────────────────────────────────────────────────┐
│ Infrastructure (adapters)                                        │
│   inbound/http/api.ml  ← projects workflow output to wire format │
│   inbound/http/http.ml ← HTTP routing                            │
│   acl/finam, acl/bcs, paper ← outbound broker adapters           │
└──────────────────────────────────────────────────────────────────┘
                              ▲
                              │ calls
┌──────────────────────────────────────────────────────────────────┐
│ Application                                                      │
│                                                                  │
│   workflows/               ← pipelines composing the steps       │
│        ▲                                                         │
│        │ composes                                                │
│        │                                                         │
│   commands/                ← inbound command DTO + validation    │
│   domain_event_handlers/   ← reactors for single domain events   │
│                                                                  │
│   queries/                 ← read-side view models (DTO)         │
│   integration_events/      ← outbound event DTOs                 │
│   rop/                     ← accumulating Result + applicative   │
│   broker/                  ← outbound port (Broker.S)            │
└──────────────────────────────────────────────────────────────────┘
                              ▲
                              │ uses
┌──────────────────────────────────────────────────────────────────┐
│ Domain (pure)                                                    │
│   core/       ← Instrument, Candle, Order, Decimal, Side, ...    │
│   engine/     ← Portfolio (aggregate, emits domain events)       │
│   strategies/, indicators/, ml/, stream/                         │
└──────────────────────────────────────────────────────────────────┘
```

## Application sub-layers

### `commands/` — what the system receives

An inbound **command** is a user-initiated action: "place this
order", "cancel this order", "run this backtest". Each lives in
its own file: `place_order_command.ml`, etc.

A command module defines:

- **`type t`** — the DTO a consumer sends: primitive-typed,
  `[@@deriving yojson]`, unvalidated.
- **`type validation_error`** — typed union of possible parse
  failures. Never `string`.
- **`type unvalidated`** — the intermediate shape after primitives
  are mapped into domain types (`Instrument.t`, `Side.t`,
  `Decimal.t`). Not yet domain-validated.
- **`val to_unvalidated : t -> (unvalidated, validation_error) Rop.t`** —
  accumulates every field's parse failure into a list, doesn't
  short-circuit on the first one.
- Step functions that this command initiates (e.g. `reserve` for
  PlaceOrder).

A command module is parameterised over *what the consumer asked
for*, not how it travels to the system. The HTTP handler in
`infrastructure/inbound/http/` is one way to deliver a command;
there can be others (CLI, message bus) in the future.

### `domain_event_handlers/` — what the system does in response

A **handler** reacts to **one** domain event. Files named like
`forward_order_to_broker.ml`, `release_reservation_on_broker_rejection.ml`.
Each file has one function:

```ocaml
val handle : ... dependencies ... -> Some.Domain.event ->
             (next_event, failure_event) Rop.t
```

Handlers are **source-agnostic**: they care about the event
type, not where it came from. The same `forward_order_to_broker`
can react to `amount_reserved` from the manual `PlaceOrder`
command or from a future strategy-driven `Entry_point_identified`
flow.

### `workflows/` — pipelines composing steps

A **workflow** is the top-level function for a specific
user-initiated action. Files named like `place_order_workflow.ml`.
Composition is explicit OCaml code, not event-bus magic: the
workflow decides which step runs next based on the previous
step's result.

```ocaml
(* place_order_workflow.ml, simplified *)
let run ~portfolio ~place_order ~... cmd =
  let (let*) = Result.bind in
  let* u = Place_order_command.to_unvalidated cmd |> ... in
  let* (p', reserved) = Place_order_command.reserve ... u |> ... in
  match Forward_order_to_broker.handle ... reserved with
  | Ok forwarded -> Ok (p', events @ [Order_forwarded forwarded])
  | Error rejection ->
    match Release_reservation_on_broker_rejection.handle ... with
    | ...
```

The workflow returns **`(Portfolio.t * event list, error) result`**:

- **Error track** — the workflow aborted before changing state
  (validation failed, reservation invariant rejected).
- **Success track** — events the workflow produced, in order.
  Each event describes a real state change. Multiple events in
  one run (reserve + forward + maybe release on rejection).

The event list is the workflow's natural output shape: an
internal audit trail of what the pipeline did. It's not a
publishing mechanism, and it's not exposed to callers as-is.
The HTTP adapter picks a terminal outcome from the list and
projects a stable minimal response — see *Stable wire contract*
below.

### `integration_events/` — outbound event DTOs

**Why a separate type at all.** A domain event carries *Value
Objects* from the domain layer — `Instrument.t`, `Side.t`,
`Decimal.t`, etc. These are opaque, private, invariant-carrying
types: `Ticker.t` is a `private string` constrained to
upper-case no-whitespace; `Decimal.t` is fixed-point with a
specific scale; `Instrument.t` is a private record whose
constructor rejects malformed venues. **None of these can be
serialised directly.** Out-of-process consumers (HTTP, message
bus, WebSocket, audit database) need primitive types: strings,
floats, ints.

So to send an event across a process boundary, a handler must
convert it into an **integration event** — a primitive-typed
copy. This is exactly analogous to the way we project
**domain models** (`Core.Order.t`, `Engine.Portfolio.t`) into
**view models** for read endpoints:

| | Domain (Value Objects, private types) | Outbound DTO (primitives, serialisable) |
|---|---|---|
| State snapshot | `Core.Candle.t` | `Candle_view_model.t` |
| Happening | `Portfolio.amount_reserved` | `Amount_reserved_integration_event.t` |

Same contract shape (`of_domain` + `yojson_of_t`), different
semantic — one captures *current state*, the other captures
*what happened*.

Each domain event has a matching integration event: a
primitive-typed `[@@deriving yojson]` copy with an `of_domain`
conversion.

These exist so a future message bus, WebSocket, or audit log can
subscribe to the workflow's events without re-implementing
projection. The workflow itself doesn't depend on
`integration_events` — the adapter projecting to a channel does.

### `queries/` — read-side view models

For read endpoints (`GET /api/orders`, etc.), domain entities are
projected into VMs in the same way:

```
Core.Candle.t  →  Candle_view_model.of_domain  →  primitive record + yojson
```

Contract: [`view_model.ml`](../../lib/application/queries/view_model.ml)
declares `module type S`; every VM conforms via a compile-time
self-check in `queries/compile_checks.ml`.

### `rop/` — accumulating Result

A thin layer over stdlib `Result` with:

- `Rop.t = ('a, 'err list) result` — Error always carries a list.
- `apply : ('a -> 'b, 'err) t -> ('a, 'err) t -> ('b, 'err) t` —
  accumulates both sides' error lists when both fail.
- `(let+)` + `(and+)` — applicative binding operators for parallel
  accumulating validation.
- `(let*)` — monadic bind, short-circuit on first error.

Pattern: applicative for independent field validation (all
errors reported together), monadic for step-by-step pipelines
(each step needs the previous to succeed).

### `broker/` — outbound port

Not new; same as in [`overview.md`](overview.md#the-core-abstraction-brokers).
The workflow receives `place_order` as an injected function
dependency (partial application of `Broker.place_order client`);
workflow itself doesn't import `broker`.

## Domain events

Events are facts about aggregate state changes. They live
**inside the aggregate** that emits them, not in the command
module that happens to trigger the aggregate call.

```
lib/domain/engine/portfolio.mli:
  type amount_reserved = { reservation_id; side; ... }      ← event
  type reservation_released = { reservation_id; side; ... }
  val try_reserve : ... -> (t * amount_reserved, ...) result
```

The aggregate method emits the event as part of its return
value; no mutable event bus inside the aggregate (that's the
Vaughn-Vernon accumulator style — we chose the Wlaschin-style
return-tuple form for PlaceOrder). See
[`reputation-bot/reputation/domain/aggregates/member/`](../../../reputation-bot/reputation/domain/aggregates/member/)
for the other flavor, for reference.

Event types used by the first workflow (PlaceOrder):

| Event | Emitted by | Triggers |
|---|---|---|
| `Portfolio.amount_reserved` | `Portfolio.try_reserve` | `Forward_order_to_broker` handler |
| `Forward_order_to_broker.order_forwarded` | handler's success | nothing (terminal) |
| `Forward_order_to_broker.forward_rejection` | handler's failure | `Release_reservation_on_broker_rejection` handler |
| `Portfolio.reservation_released` | `Portfolio.try_release` | nothing (terminal) |

## Stable wire contract

**Rule: domain events never cross the HTTP boundary.**

Two reasons:

1. **Information disclosure.** Internal ids, broker error
   strings, state-machine topology — none of that should leak to
   a public client. Events are designed for internal trust
   zones.
2. **Coupling.** If the browser parses event shapes, every
   internal refactor (rename, split, add field) breaks the
   frontend. A stable public response insulates the client from
   domain evolution.

HTTP adapter (`inbound/http/api.ml`) projects the workflow's
event list into a **minimal stable response**:

```ocaml
let place_order_response_json events =
  let forwarded = List.find_map ... in
  let rejected  = List.find_map ... in
  match forwarded, rejected with
  | Some f, _ -> `Assoc [ "status", `String "placed"; "order", ... ]
  | None, Some (Order_rejected_by_broker {reason; _}) ->
      `Assoc [ "status", `String "rejected"; "reason", ...]
  | None, Some (Broker_unreachable _) ->
      `Assoc [ "status", `String "temporary_error"; ...]
  | None, None -> ...
```

Three terminal outcomes → three possible response shapes. Adding
a new domain event inside the workflow changes the internal list
but **not** the HTTP contract. Renaming an event is safe. Only
adding a genuinely new *terminal business outcome* (e.g.
`partial_fill_at_submit`) changes the wire response — and that's
a deliberate product decision, not a refactor side effect.

## Direction of knowledge

```
infrastructure → knows → application
application   → knows → domain
domain       → knows → (nothing outside itself)

queries / integration_events ← project ← domain entities / events
```

Specifically for application sub-layers:

- `commands/` imports `core`, `queries`, `rop`
- `domain_event_handlers/` imports `core`, `engine`, `rop`
- `workflows/` imports `commands`, `domain_event_handlers`, `core`, `engine`, `rop` — this is the only sub-layer that imports multiple peers, because it composes them.
- `integration_events/` imports `core`, `engine`, `queries`, `domain_event_handlers` — for the domain-event types it projects.
- `queries/` imports `core`, `engine` only.

`infrastructure/inbound/http/` imports everything in application
as needed. That's the hexagonal entry-point.

## Design decisions

Stated once; don't re-argue per command.

1. **Commands and handlers are separate.** A command module
   represents a user-initiated driving port. A handler represents
   a reaction to an event. They compose inside a workflow, but
   their files don't overlap — a new handler doesn't need a new
   command, and vice versa.

2. **Errors are typed unions, never strings.** Every
   `validation_error`, `reservation_error`, `forward_rejection`
   is a discriminated union. Strings are for humans; code
   pattern-matches types.

3. **Domain events are aggregate-level.** Emitted by
   `Portfolio.try_reserve`, not synthesized by the command
   handler from parameters. The aggregate is the source of
   truth for "what happened to me".

4. **Compensation is a railway switch, not an undo.**
   `release_reservation_on_broker_rejection` is a *normal*
   handler reacting to a failure event. There's no SAGA-style
   rollback — the reservation wasn't "committed" yet, just
   earmarked, so releasing it is a forward action on a
   different track.

5. **Event list as workflow output is internal.** Not a batch
   publish mechanism (there is no bus yet), not a wire payload.
   It's just a structured return value describing the pipeline's
   trace. The HTTP adapter picks what's relevant.

6. **Integration events exist for future subscribers.** They
   live in application layer despite being DTO-shaped. When a
   message bus / WebSocket fan-out arrives, they're the natural
   envelope. No work required in the workflow itself.

7. **Naming: `cmd`, not `dto`.** DTO is an architectural
   category (data transfer); `cmd` says what it is semantically
   (a command). View models are `Candle_view_model`, not
   `Candle_dto`. Integration events are `*_integration_event`.
   Type describes intent.

8. **`let+ / and+` for applicative, `let*` for monadic.** Parse
   multiple DTO fields in parallel with accumulation — use
   `let+ / and+`. Chain dependent steps (reserve → forward) —
   use `let*` or explicit `match` (when failure-branch needs
   compensation).

## Example: PlaceOrder end-to-end

```
┌── infrastructure/inbound/http ──────────────────────────────────┐
│                                                                 │
│   POST /api/orders                                              │
│     body JSON                                                   │
│         │                                                       │
│         ▼                                                       │
│   Place_order_command.t_of_yojson                               │
│         │                                                       │
│         ▼                                                       │
│   Place_order_workflow.run ────────────────────────┐            │
│                                                    │            │
│   response: Api.place_order_response_json events    │            │
│              → 200 or 400                           │            │
└─────────────────────────────────────────────────────│────────────┘
                                                     │
┌── application ──────────────────────────────────────│────────────┐
│                                                    ▼            │
│                                         Place_order_workflow    │
│                                          ┌──────┬─────┬──────┐  │
│                                          │ step │step │step  │  │
│                                          │  0   │ 1   │ 2    │  │
│                                          ▼      ▼     ▼      ▼  │
│                         Place_order_command.to_unvalidated      │
│                         Place_order_command.reserve             │
│                         Forward_order_to_broker.handle          │
│                         Release_reservation_on_broker_rejection │
│                         (on failure branch only)                │
└─────────────────────────────────────────────────────────────────┘
                          │         │         │
                          ▼         ▼         ▼
┌── domain (aggregates) ──────────────────────────────────────────┐
│    Portfolio.try_reserve ─► amount_reserved event               │
│    Portfolio.try_release ─► reservation_released event          │
└─────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌── infrastructure/acl ───────────────────────────────────────────┐
│    Broker.place_order (via Finam/BCS/Paper adapter)             │
└─────────────────────────────────────────────────────────────────┘
```

Notes on the flow:

- Steps 0, 1 are pure; no broker interaction, no IO.
- Step 2 is the only IO call — through the injected
  `place_order_port`, so the workflow doesn't depend on `Broker`
  directly.
- Failure of step 0 or 1 is **before** any state change → return
  `Error _`, no events emitted.
- Failure of step 2 is **after** reservation → emits the failure
  event, triggers release handler, emits `reservation_released`,
  returns `Ok (portfolio', events_with_both)`.
- HTTP adapter sees the event list and projects `placed` /
  `rejected` / `temporary_error` from it.

## What's *not* here

- **Event publishing infrastructure.** No message bus, no
  WebSocket fan-out of events, no audit database. When those
  arrive, they'll subscribe to workflow events without
  modifying the workflow itself.
- **Second command.** Only `PlaceOrder` is implemented. `CancelOrder`,
  `RunBacktest`, `StartLiveStrategy` are planned.
- **HTTP wiring of the workflow.** The pipeline is built but
  `POST /api/orders` still points at the legacy direct-broker
  path. Wiring is next.

## See also

- [`overview.md`](overview.md) — the base hexagonal structure
- [`domain-model.md`](domain-model.md) — the types flowing
  through commands and events
- [`state-machine.md`](state-machine.md) — how bars become
  intents (this is the strategy-driven path, orthogonal to
  manual commands)
- [`reservations.md`](reservations.md) — how Portfolio earmarks
  cash/qty and the reserve → commit lifecycle
