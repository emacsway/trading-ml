# Order flow — footprint analysis on the public tape

Until the `order_flow` bounded context landed, the system saw the
market only as OHLCV bars. A bar tells you the open, high, low, close
and total volume of a period — but not *who* traded: how much of that
volume lifted the ask (aggressive buyers) versus hit the bid
(aggressive sellers). That buy/sell split, resolved **per price
level**, is the *footprint* (a.k.a. cluster / volumetric / numbers
bars); its running sum is *cumulative volume delta* (CVD). The
strategy BC's `CVD` indicator used to *approximate* the split from the
close's position inside the bar range — its own doc comment admits
"bar data carries no true bid/ask split." `order_flow` replaces the
guess with ground truth, reconstructed from the **public trade
stream**.

This page explains how that capability is shaped: the BC boundary, the
domain model and its lifecycle, the broker trade relay that feeds it,
the cross-BC value loop into `strategy`, how it is backtested, and what
is formally proved versus tested. The decisions themselves — and the
alternatives weighed — are recorded in
[ADR 0032](../adr/0032-order-flow-bounded-context.md); this page is the
*how*, the ADR is the *why*.

## Why a separate BC

Order-flow analysis is its own bounded context, not a module inside
`strategy`. The split is sharp:

- **`order_flow`** answers *"what is the shape of the order flow"* —
  objective facts about the tape: per-price clusters, bar delta, POC,
  an OHLCV reconstructed from prints.
- **`strategy`** answers *"what do I do about it"* — thresholds,
  divergences, signals.

Two forces make this a boundary rather than a folder. First,
**vocabulary**: the microstructure language (cluster, delta, POC,
value area, absorption, aggressor) is self-contained and must not leak
into the strategy domain. Second, **data tier**: the tape is a
tick-level firehose, an entirely different scale and lifecycle from the
light signal path — the independent-deployability argument for a BC.
Per the system's [dependency rule](bounded-contexts.md#the-dependency-rule),
`order_flow` shares no types with its neighbours; it talks to them only
through integration events on the bus.

## The pipeline

`order_flow` sits on an **analytics branch** off the broker's tape,
parallel to the place-order saga the
[main BC map](bounded-contexts.md#the-map) traces:

```
  broker                      order_flow                       strategy
  ──────                      ──────────                       ────────
  public-trade WS             ingest each print into the       footprint engine
  (Finam / BCS / Alor)        current bar's Footprint          (Cvd_divergence)
        │                            │                               │
        │  Trade_printed_IE          │  per print:                   │
        ├───────────────────────────►  open_ / classify / absorb    │
        │  broker.public-trade-printed      │                               │
        │                            │  at period edge: seal,        │
        │                            │  emit Footprint_completed     │
        │                            ├───────────────────────────────►
        │                            │  order-flow.footprint-completed│
        │                            │                               │  on_footprint:
        │                            │                               │  CVD vs price
        │                            │                               │  divergence
        │                            │                               ▼
        │                            │                        strategy.signal-detected
```

Each hop is a wire-format integration event (primitives only, decimals
as canonical strings, ISO-8601 timestamps — the
[IE canon](bounded-contexts.md#the-integration-event-canon)). The
consumer mirrors the producer's DTO in its own
`infrastructure/acl/external_integration_events/`, so no type is
shared across the boundary.

## The domain model

The domain lives under `order_flow/lib/domain/footprint/`, in the
standard [per-aggregate layout](../adr/0006-domain-layer-per-aggregate-layout.md)
(`values/`, `events/`, aggregate root). Four value objects and one
aggregate carry the model; each has a Why3 companion (`.mlw`).

### `Footprint` — an aggregate with a lifecycle, not a projection

A footprint *looks* like a pure projection of an immutable trade
stream — no command rejects a trade, so why an aggregate? Because the
real policy decisions live at the **edges**, and that is exactly what
an aggregate is for:

- **Immutability after seal** — a `Sealed` bar is never mutated.
- **Partition** — each print belongs to exactly one bar.
- **Conservation** — total cluster volume equals the sum of accepted
  print sizes.
- **Late / out-of-order policy** — a print whose bucket precedes the
  open bar's is *late*; the aggregate refuses it (it does not reopen a
  sealed bar). The application decides the disposition (drop, log,
  metric).

So `Footprint` is an aggregate root with lifecycle `Forming → Sealed`
and transitions `open_ / classify / absorb / seal`, a single bar as its
consistency boundary. Rolling to the next bar (seal current, open next)
is sequenced by the **application layer**, which holds the current bar
per instrument — mirroring how the Account handler holds its
`Portfolio`. The aggregate keeps running `volume` and `delta`
accumulators that are the source of truth for the bar's totals.

### `Aggressor` — three states, not `Core.Side`

`Core.Side` is the direction of an *order* and has two inhabitants.
`Aggressor` classifies an *executed print* and admits a third —
`Indeterminate` — for prints with no initiator: opening/closing auction
crosses and negotiated off-book trades. Reusing `Side` would erase that
case and force a false buy/sell choice onto directionless volume.

`Aggressor.sign` is `+1 / -1 / 0`, and the **`0` is load-bearing**: it
keeps auction volume in *total* but out of *delta*. On MOEX the auction
is often the largest single event of the session; silently folding it
into buy or sell would corrupt both POC and delta.

### `Cluster` — three buckets and an algebra

Each `Cluster` (one price level) holds `buy_volume`, `sell_volume`,
`indeterminate_volume`. Two derived quantities define the algebra:

```
total = buy + sell + indeterminate      (all volume at this price)
delta = buy − sell                        (signed pressure; auction excluded)
```

`Cluster.add` folds a classified print into the right bucket. Its
**commutativity** — `add a (add b c) = add b (add a c)` — is the formal
kernel of *fold-order independence*: reordering prints within a bar
yields the same cluster, which is what makes the footprint a function
of the *set* of prints, not their arrival order.

### `Bar_boundary` — a polymorphic seam

`Bar_boundary` is a variant: `Time of Core.Timeframe.t` and
`Volume of Decimal.t` are implemented; `Tick` is the next planned case
and drops in the same way — a new constructor, not a rewrite. The seam
lives in the type, exposed via `admits_time_close` (Time bars must
close at the period edge even in a silent market; Volume/Tick bars
close only on the print that crosses the threshold). Time bars were
chosen *first* deliberately: they reuse the existing `Timeframe`, align
with the broker's candle grid, and give a free reconciliation oracle —
a Time footprint's own OHLC must agree with the venue candle for the
same period. The factory defaults to `Time M5`; a composition can pass
`~boundary:(Bar_boundary.Volume cap)` to switch, touching nothing else.

**What adding `Volume` actually cost.** The seam held where it was
designed to: the integration event, the ingest handler, the workflow,
and the downstream strategy are unchanged; `absorb`/`seal` and their
Why3 accumulator laws are unchanged (they are boundary-agnostic). Two
things in the aggregate gained a `Volume` case — `classify` (membership
is "has the running volume reached `cap`?" instead of a timestamp
bucket) and `open_` (a Volume bar opens at the first print's own `ts`,
with no time grid). Two honest costs surfaced that the original
"new variant, zero churn" framing glossed over: `bucket_start` and
`period_seconds` are Time-shaped and became **partial** (they raise on
`Volume`, which the aggregate never calls there); and the **fold-order
independence** argument does *not* carry to Volume — a Volume bar's
*partition* depends on arrival order (which print first fills the bar),
even though the cluster algebra within any fixed bar still commutes.
No Why3 goal broke, because none encoded the Time-specific partition;
the order-independence claim is scoped to Time in the boundary's docs.

**Close policy: no-split (for now).** The print that tips the bar over
`cap` is absorbed whole, so a sealed Volume bar may slightly exceed
`cap` by that print's overshoot. The exact-cap alternative — splitting
the tipping print across two bars (Lean's `VolumeRenkoConsolidator`
leftover-loop) — is a documented follow-up; for a footprint it must
split the print's *signed* volume across both bars' per-price clusters
while preserving per-bucket conservation, so it is a domain decision
with its own proof obligation, deferred behind this same seam rather
than hidden in the consolidator.

ADR 0032 §5 records why we did *not* start with the
information-theoretically superior volume/dollar bars (de Prado): they
would couple bring-up to a still-unproven trade relay and forfeit the
candle oracle. The hard parts of this BC are aggressor handling, the
cluster algebra and its proofs, and the relay — not the boundary.

## Aggressor semantics and the side question

The whole delta pyramid rests on one assumption: **does the venue's
`side` field mark the *aggressor* (initiator) or the *resting* order?**
An inversion would flip every delta-based signal. All three supported
venues are MOEX-based and, by the continuous-double-auction convention,
report the aggressor's side:

| Venue | Channel | `side` values | Maps to |
|-------|---------|---------------|---------|
| Finam | `INSTRUMENT_TRADES` (WS) | `SIDE_BUY` / `SIDE_SELL` / `SIDE_UNSPECIFIED` | Buy / Sell / Indeterminate |
| BCS   | `dataType:2` (LastTrades) | `BUY` / `SELL` / (other) | Buy / Sell / Indeterminate |
| Alor  | `AllTradesGetAndSubscribe` | `buy` / `sell` / (other) | Buy / Sell / Indeterminate |

The mapping is a **single point per adapter** (`parse_side`), so an
inversion, if ever found, is a one-line flip. Anything not explicitly
marked stays `Indeterminate` — the tape never fabricates direction.

This assumption is **validated empirically**, not assumed. The
live-smoke probes subscribe to L1 quotes and the tape together and
check each print against the prevailing bid/ask: a BUY print sitting at
the ask (and SELL at the bid) confirms `side` is the aggressor; the
reverse would flag inversion.

- **Finam — confirmed** (live SBER@MISX, 2026-05-27, via
  `broker/test/live_smoke/finam_public_trades_probe`).
- **BCS — pending.** Relay built; probe ready
  (`bcs_public_trades_probe`), to be run against a live token.
- **Alor — pending.** Relay built; validation deferred until the
  account opens.

## The broker trade relay

Feeding `order_flow` required a new data tier in the broker BC, which
previously relayed only bars. A `Remote_public_trade_updated` domain
event (`side : Core.Side.t option`, `None` = auction/indeterminate) is
emitted per print and published as `Public_trade_printed_integration_event` on
`broker.public-trade-printed`. The three adapters differ in WS topology — see
[websocket-protocol-layer.md](websocket-protocol-layer.md) for the
shared client:

- **Finam** multiplexes every subscription over one socket
  (`ws_bridge`); the tape is one more channel (`INSTRUMENT_TRADES`)
  alongside bars and quotes.
- **BCS** dedicates **one socket per channel per instrument**. The tape
  socket is **WS-only** — BCS exposes no REST history for the public
  tape, so unlike the bars channel there is no
  [transport-supervisor](transport-supervisor.md) REST fallback.
- **Alor** multiplexes over one socket and correlates every inbound
  frame back to its subscription by `guid`; the tape
  (`AllTradesGetAndSubscribe`) registers its `guid` like any other
  channel.

The factory subscribes the public tape for each distinct instrument in
the watchlist, refcounted so overlapping subscriptions share one
socket.

## Backtesting: tick replay

A footprint needs a *tape*, not just bars — so the backtest path moved
to tick replay. Two tape sources exist:

1. **Synthetic tape.** `Synthetic.Trade_generator` expands each
   backtest candle into a sequence of prints that reconstruct its OHLC,
   published on `broker.public-trade-printed`. The full footprint loop runs
   offline with no network. The `VirtualClock`
   ([ADR 0013](../adr/0013-clock-injection.md)) stays on the bar
   stream; the footprint uses each *print's own* `ts`, not ambient
   time. Caveat: the synthetic delta is *generated*, so it validates
   footprint **mechanics**, not microstructure **alpha**.

2. **Recorded tape.** Any probe run with `--record FILE` writes the
   live tape as one `Trade_printed` JSON per line — the exact wire
   shape `backtest --tape FILE` replays. This is how real microstructure
   is evaluated offline.

The [how-to guide](../howto/footprint-backtest.md) walks through both.

## What is proved, and what is tested

The formal-verification scope is drawn honestly
([ADR 0032 §8](../adr/0032-order-flow-bounded-context.md)). The Why3
companions **prove**, at the value level: the cluster algebra
(`delta = buy − sell`, `total = sum of three`, non-negativity preserved
by `add`) and `add` **commutativity** (the fold-order-independence
kernel); the print invariant (`size > 0`); and the Time-bucket
arithmetic. At the aggregate level, on the running `volume` / `delta`
accumulators: **conservation** (`absorb` grows volume by exactly the
print size), the **delta law** (`delta` moves by `sign(aggressor) ·
size`), and the lifecycle laws (`seal` freezes status and preserves
totals).

What is **not** push-button SMT-provable is left to construction +
tests, and said so plainly: the list-sum equivalence ("sum of cluster
totals equals `volume`") holds by construction via the per-step
`Cluster.add_conserves_total` law and is covered by a QuickCheck
property; POC / high / low are projections, not invariants, and are
unit-tested. We do not overclaim what the proofs cover.

## Integration with `strategy`

`strategy` consumes `order-flow.footprint-completed` through a
`Footprint_strategy` abstraction (`on_footprint`). The one concrete
implementation today is `Cvd_divergence`: it tracks real cumulative
volume delta against price over a lookback window and emits a signal
when they diverge (price makes a high while CVD does not, or vice
versa). The factory wires it always-on under `strategy_id`
`FootprintCVDDivergence`.

This is where `order_flow`'s *true* delta meets the strategy's older
*proxy* CVD indicator. They coexist on purpose (ADR 0032 §7): the proxy
remains a valid fallback for candle-only instruments and synthetic
backtests, while the footprint path carries ground truth where a real
tape is available. Making the proxy a *fallback* of the true feed is a
later cross-BC integration, deliberately out of scope for now.

## See also

- [ADR 0032](../adr/0032-order-flow-bounded-context.md) — the decision
  record (boundary, lifecycle, aggressor, formal scope, alternatives).
- [How-to: footprint backtest and tape recording](../howto/footprint-backtest.md).
- [Bounded contexts](bounded-contexts.md) — where `order_flow` sits in
  the system graph.
- [Transport supervisor](transport-supervisor.md) — the WS/REST
  failover the bars channel uses (and the tape, on BCS, deliberately
  does not).
