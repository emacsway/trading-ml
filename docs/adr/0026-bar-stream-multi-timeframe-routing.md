# 0026. Bar streams as first-class subscriptions; multi-timeframe routing through domain BCs

**Status**: Proposed
**Date**: 2026-05-20

## Context

The PM construction pipeline today rests on an **unspoken
single-timeframe assumption**: every rolling-window estimator
(Vol_state, Pair_mr_state regression, future indicators),
every mark-refresh cadence, and every annualisation factor —
all consume the same bar stream selected at broker startup.
The DTO carries `timeframe : string`, but no subscriber
filters on it, no admin command names it, and no construction
policy declares its dependence on it.

This works as long as the installation runs one timeframe.
Several real drivers will break it:

1. **Multi-timeframe broker publish.** Today `broker.bar-updated`
   is a single URI; subscribers (Strategy, PM) take whatever
   comes through. A future operator who wants both 5m bars
   (for Strategy momentum) and 1h bars (for PM vol estimation)
   forces either (a) two installations or (b) timeframe
   filtering at the bus layer — neither of which exists.

2. **Per-policy temporal horizon.** A book running fast
   mean-reversion wants short rolling windows on short bars;
   another book running portfolio rebalance wants long
   windows on long bars. Today every book on the same
   installation gets the same timeframe — the slowest book
   compromises for the fastest, or vice versa.

3. **Annualisation correctness.** The 252 factor in
   `Vol_state` is right only for daily bars. Hourly intraday
   US equity needs ~1638; crypto 24/7 needs ~8760. A single
   global constant is operationally fragile: an operator who
   swaps the broker timeframe from daily to hourly without
   touching `Vol_state` annualisation gets silently-wrong
   volatility estimates.

4. **Multi-leg synchronisation.** Pair_mr's `on_bar`
   implicitly assumes leg-A and leg-B bars arrive on the same
   timeframe. A multi-timeframe stream — even on the same
   instrument pair — desynchronises the ring buffer and
   produces nonsense z-scores.

The construction → sizing pipeline is largely
timeframe-independent at its core (clip, apply, diff are pure
state transitions over snapshots). But everything **upstream**
of `Construction_intent` that uses rolling history is bound
to the bar stream's timeframe.

The need is not academic — when production goes live with
more than one realistic operator workflow, this becomes
load-bearing. The shape of the migration is worth fixing now
even though the implementation is deferred until a driver
appears, so the team does not have to re-derive the reasoning.

## Decision

Adopt the following architectural intent. Implementation
deferred until a concrete operator workflow requires it; the
ADR fixes the **shape** so the migration is mechanical when
the driver materialises.

### A. Admin commands flow through owning BC, not through broker

A request "subscribe instrument X on timeframe Y" comes from
admin (HTTP / CLI). It is **not** routed directly to the
broker BC. Instead:

```
admin POST /api/strategy/bar_subscriptions      (Strategy is owner)
          │ {instrument, timeframe}
          ▼
   Strategy BC accepts command, validates, persists locally,
   dispatches Subscribe_to_bar_feed_command to broker BC via bus,
   subscribes its own consumer to the partitioned topic.

admin POST /api/portfolio_management/bar_subscriptions
          │ {instrument, timeframe}  (PM is owner)
          ▼
   PM BC accepts command, validates, persists locally,
   dispatches Subscribe_to_bar_feed_command to broker BC,
   subscribes its own consumer to the partitioned topic.
```

Each domain BC **owns** the lifecycle of its own bar
subscriptions. Broker BC is a publisher; it does not decide
who consumes what. This keeps the routing decision in the
domain that has the requirement.

### B. Bus topic partitioning by `{instrument}-{timeframe}`

Broker BC publishes each bar to a partitioned URI:

```
in-memory://broker.bar-updated/{instrument}-{timeframe}
```

e.g.

```
in-memory://broker.bar-updated/SBER@MISX-h1
in-memory://broker.bar-updated/SBER@MISX-d1
in-memory://broker.bar-updated/GAZP@MISX-h1
```

Subscribers select by full URI; the bus layer needs no field
filter. Each `(instrument, timeframe)` pair is an independent
publication line — a domain BC subscribes to exactly the lines
it cares about. Adding a third instrument or a fourth
timeframe means adding partitions; nothing changes for
existing subscribers.

Practical consequence for the in-memory bus: the consumer
group key gains the partition in its name (e.g.
`portfolio-management-mark-h1` vs `portfolio-management-vol-d1`)
so the same BC can consume two different timeframes without
collision.

### C. Pre-warm via synchronous CQRS-Query to broker BC

When a domain BC begins consuming a partition, it has zero
state for that `(instrument, timeframe)`. To avoid the warmup
silence (vol-target zero-sizing for the first N bars), the BC
issues a synchronous outbound `Get_recent_candles_query` to
broker BC:

```ocaml
(* Domain BC, on starting a new subscription. *)
let candles =
  Broker_external_queries.Get_recent_candles_query.execute
    ~instrument ~timeframe ~count:30
in
List.iter (fun c -> update_vol instrument ~close:c.close) candles;
List.iter (fun c -> update_mark instrument ~close:c.close) candles
```

The broker BC answers either from its own in-process recent-
candles cache (if it has been running long enough) or by an
upstream REST hit to Finam / BCS. The query is one-shot, has
no event-sourcing component, and **is not persisted in PM** —
the bars are replayed through the existing update closures and
discarded. If PM restarts, the query fires again on
re-subscription.

This is **explicitly cheaper than a persistence layer**. We
do not need to backfill PM's own database with historical
candles to recover state; we recover by re-asking the broker.
The persistence layer (Transactional Outbox) is reserved for
**authored** state (Risk_configs, Alpha_subscriptions, Pair_mr
configs, Target_portfolios) — for **derivable** state
(Vol_state, mark cache) the re-fetch path is sufficient.

If at some future date broker re-fetch becomes too expensive
(rate limits, latency on cold start), the answer is **broker-
side persistence** of recent candles (a small ring buffer per
partition), not PM-side persistence of vol state. The
boundary stays clean.

### D. `Bar_stream` as a first-class abstraction above policies

Today's construction policies have an implicit dependency on
"the bar feed". This dependency becomes explicit:

```ocaml
(* domain/common/bar_stream.ml *)
type t = {
  instrument          : Core.Instrument.t;
  timeframe           : Timeframe.t;
  annualisation_factor : float;
}
```

- `Timeframe.t` — a typed enum (`M1 | M5 | M15 | H1 | H4 | D1 | W1 | Mo1`),
  not a string. Parsing happens once at the wire boundary.
- `annualisation_factor` — derived from timeframe, not
  re-supplied per call site. A single computation
  (`Timeframe.annualisation_factor` function) gives the right
  number for the asset class:
    * equities (252 trading days / year):
      - D1 → 252
      - H1 → 252 × 6.5 = ~1638 (US intraday)
      - M5 → 252 × 6.5 × 12 = ~19656
    * crypto (24/7):
      - D1 → 365
      - H1 → 365 × 24 = 8760

  Asset-class selection itself is a separate config layer;
  for now derived from a global `Calendar` parameter.

Construction policies that consume rolling history reference
a `bar_stream_id` (or carry the `Bar_stream.t` directly):

- `Pair_mr_config` gains `bar_stream : Bar_stream.t`.
- `Volatility_view` (per (D)) carries `bar_stream : Bar_stream.t`.
- Future indicators do the same.

Mark cache is per-`Bar_stream` too — different timeframes have
different "last close" semantics; a daily mark and an hourly
mark on the same instrument are different sources of truth
and the cache must keep them separate.

**Why3 invariant** (per book, for the single-stream case):
*every construction policy on a single book that uses temporal
reasoning must reference the same `bar_stream_id`*. This is
the "sanity" invariant; deliberate per-policy timeframe
divergence (vol on D1, pair_mr on H1) is allowed only by
explicit operator opt-in via a per-policy override field.

### E. `Volatility_view` aggregate — V2 or V3 (deferred choice)

The per-(book, instrument, timeframe) volatility provider
becomes a first-class domain construct. Two plausible shapes:

- **V2 — full aggregate** (`domain/volatility_view/`): own
  lifecycle, `Define_volatility_view_command`, ATD wire
  contract, HTTP route, optional `Volatility_observed`
  integration event for cross-BC publication. Right choice if
  any other BC (Risk_management, UI dashboard) needs to
  observe vol.

- **V3 — lightweight Vol_view registry referenced from
  Risk_config**: vol view is a VO with config + state;
  registry keyed by `Vol_view_id`; `Risk_config.vol_view_id :
  Vol_view_id option`. Multiple books can share a view.
  Cheaper, no cross-BC publication, no HTTP route.

The choice depends on whether external observers of vol
appear. If they do — V2; if they remain PM-internal — V3.
Either way, the abstraction sits above the policy layer:
`Volatility_target.size` consumes a `Volatility.t` from a
provider, and the provider is backed by a Vol_view, not by a
loose registry.

## Answer to: "should PM volatility have the same timeframe
as the rest of PM, or can they differ?"

**Conceptually they may differ.** The three PM consumers of
the bar stream have different natural horizons:

| Consumer | What it reads bars for | Natural horizon |
|---|---|---|
| Mark cache | Current valuation for sizing / equity | Fastest available (low timeframe is better — fresher equity) |
| Vol estimator | Annualised risk budget | Medium-long (D1 typical; weekly window for stability) |
| Pair_mr regression | Cointegration / spread mean | Bound to the strategy (intraday for HFT pairs, daily for stat-arb) |

Mathematically there is no constraint that vol's annualisation
basis must equal pair_mr's window basis must equal mark
cache's refresh rate. Aladdin-class portfolio systems
deliberately separate them: marks refresh per-tick, vol
estimates roll over weekly or monthly windows, factor
regressions over multi-year history.

**Pragmatically, in the first migration step, force them to
match per book.** Operator configures one `Bar_stream` per
book; vol view, pair_mr, mark — all reference that stream.
Why: (1) it preserves the Why3-checkable single-stream
invariant per book, (2) it eliminates the equity-vs-vol-skew
class of bugs where mark refresh frequency outruns or lags
vol-target reactivity, (3) it is operationally
understandable.

**Later, allow per-policy override.** Once V2/V3 lands, the
operator may explicitly opt-out of the single-stream
invariant on a specific book: "this book sizes against D1
vol but flips on H1 alpha". The override is a `Bar_stream.t`
override field on the policy config, and the Why3 invariant
becomes conditional ("either the policy declares an override
or it inherits the book's default stream"). The override is
deliberately verbose so it is visible to audit.

So the answer:

> Today (single-stream world): same timeframe across the
> book, no choice. Tomorrow (Bar_stream world): the same by
> default, divergent only by deliberate per-policy override.

This shape lets the first migration introduce `Bar_stream`
without enabling divergence — divergence is the second
migration once V2/V3 lands.

## Alternatives considered

### Single URI with bus-side filter

Keep `broker.bar-updated` as one topic; let subscribers say
"give me only `timeframe = h1`" via a filter middleware.

Rejected because:

- In-memory bus has no notion of message filtering at the
  consumer-group layer; adding one is a separate piece of
  infrastructure with its own surface.
- Subscribers would still need to know the timeframe they
  want — the partitioned URI puts that knowledge in the URI
  itself, which is observable / debuggable. Filter middleware
  hides it behind code.
- Migration to a real broker (Kafka, NATS) is simpler when
  partitions are URI-level: Kafka topics map cleanly,
  NATS subjects are partition-shaped natively. Filter
  middleware is a custom protocol that does not transfer.

### PM-side persistence of vol state

Snapshot `Vol_state` to disk on shutdown, reload on startup.

Rejected because:

- Pre-warm via broker query achieves the same recovery
  without introducing a persistence dependency for PM.
- Snapshot semantics are subtle: a snapshot of a 20-bar ring
  buffer at t=t0 vs the same buffer reconstructed from 30
  fresh historical bars at t=t1 — they diverge in known
  small ways; downstream sizing is sensitive to this
  divergence. The "always re-pre-warm" path is **deterministic
  given broker history**; persistence is "deterministic given
  PM history" — different operational stories.
- Persistence is reserved for authored state (commands,
  configs, aggregates) where re-creation cost is high; derived
  state belongs to the re-derive path.

### Broker BC owns subscription routing

Broker BC accepts admin requests, decides which downstream
BC gets which feed.

Rejected because: violates BC boundaries. PM decides its own
data needs; Strategy decides its own. Broker is a supplier,
not an orchestrator.

## Consequences

**Easier:**

- Per-policy timeframe choice without re-installation.
- Multi-timeframe broker publishing (a single setup serves
  both Strategy on 5m and PM on 1h).
- Pre-warm becomes a one-liner per BC at startup; no
  persistence story needed.
- `Bar_stream` as an explicit type makes the
  one-stream-per-book invariant Why3-checkable.

**Harder:**

- More URIs in the bus map; debugging requires knowing the
  partition convention.
- `Subscribe_to_bar_feed_command` (broker-side) and per-BC
  `Subscribe_local_consumer_command` add admin surface.
- The annualisation_factor table (per timeframe × asset
  class) needs to live somewhere — likely
  `domain/common/timeframe.ml` with a `Calendar` parameter.
- `Volatility_view` lifecycle (V2 or V3 choice) is its own
  follow-up.

**To watch for:**

- Multi-leg policies (pair_mr) with legs on different
  timeframes — synchronously consuming two partitions for
  one decision is non-trivial. The pragmatic answer:
  pair_mr's `bar_stream` covers both legs (both subscribed
  to the same timeframe); legs on different timeframes are
  rejected by the smart constructor.
- Strategy BC subscription path is symmetric to PM's but
  Strategy currently has a single global consumer group
  `strategy-engine`. When this ADR lands, Strategy gets its
  own per-(instrument, timeframe) consumer groups too —
  refactoring scope.
- Broker BC needs a `Get_recent_candles_query` port and a
  per-partition in-process candle cache for the pre-warm
  path. Provider implementations (Finam, BCS) already have
  the REST capability; surfacing it as a CQRS query is the
  new part.

## Migration sketch (when a driver appears)

Approximate PR order for when the work begins:

1. `domain/common/timeframe.ml` — enum + annualisation_factor.
2. `domain/common/bar_stream.ml` — VO carrying (instrument,
   timeframe, annualisation_factor).
3. Broker BC: partitioned topic publication; subscribe
   command; recent-candles query.
4. PM: subscribe-bar-feed command + handler; per-partition
   subscription wiring in factory.
5. PM: pre-warm closure at subscription start.
6. PM: `Volatility_view` (V2 or V3 per E above) consuming
   `Bar_stream`.
7. PM: pair_mr_config carries `bar_stream`; Pair_mr_state
   smart constructor enforces leg-stream sameness.
8. Risk_config: per-book default `bar_stream`; per-policy
   override field (V2 phase).
9. Why3: single-stream invariant per book.
10. Strategy BC: same shape — its own
    Subscribe_to_bar_feed command, per-partition consumers.

Each step is independent enough to ship in isolation;
together they replace the implicit single-timeframe
assumption with explicit per-policy stream binding.

## References

- ADR 0023 — Broker bar feed into execution_management;
  precedent for one-subscriber-multiple-ports pattern.
- ADR 0024 — Equity-anchored sizing; this ADR strengthens
  its "To watch for" around per-instrument vol.
- ADR 0025 — Volatility_target sizing; this ADR addresses
  its "global window/factor" caveat.
- `portfolio_management/lib/factory.ml` — current
  single-subscription wiring.
- `broker/lib/factory.ml` — current single-publication URI.
- `strategy/lib/factory.ml` — current single-consumer-group
  subscription.
- `shared/contracts/broker/integration_events/bar_updated_integration_event.atd` —
  bar DTO carrying the timeframe field that today is unused.
