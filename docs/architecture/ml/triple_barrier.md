# Triple-barrier labelling

A path-sensitive alternative to the "sign of forward return"
labelling used by the threshold mode of
[`export_training_data`](../../../bin/export_training_data.ml).
Produces the same three-class output (`0 = down`, `1 = flat`,
`2 = up`) — nothing downstream changes — but derives each label
from **what actually would have happened** if the sample bar had
been traded with a TP/SL bracket.

Based on Marcos López de Prado, *Advances in Financial Machine
Learning* (2018), §3.

## What it computes

For each anchor bar `t`:

1. Compute `ATR(14)` at `t` — local volatility measure.
2. Place two barriers relative to `close[t]`:

   - take-profit: `close[t] + tp_mult × ATR[t]`
   - stop-loss:   `close[t] - sl_mult × ATR[t]`

3. Walk forward bars `t+1, t+2, …, t+timeout`. At each bar check
   whether `high[τ]` crossed the TP barrier or `low[τ]` crossed
   the SL barrier.
4. **Label = whichever barrier fired first.**

   - TP hit first → class `2` (up)
   - SL hit first → class `0` (down)
   - Neither fired within `timeout` → class `1` (flat)

The `triple` in "triple barrier" is those three exit modes — up,
down, time.

## Why path-sensitivity matters

A bar's threshold label depends only on `close[t + horizon]` —
one point in the future. That misses every intra-window
excursion:

```
  close[t] = 100
  t+1: high=103, low=99, close=99
  t+2: high=99,  low=95, close=97
  t+3: high=98,  low=95, close=95
  ─────────────────────────────────
  threshold(horizon=3, θ=0.01):  (95 - 100) / 100 = -5%  → class 0 (down)
  triple-barrier(tp=+2%, sl=-2%):  bar t+1 touched high=103 > 102 before
                                   any bar's low crossed 98 — TP hit first
                                   → class 2 (up)
```

Both are "correct" given their definitions, but they describe
different things:

- The threshold label says "where was the price at `t+3`?"
- The TB label says "if you had entered at `close[t]` with a
  `+2% / -2%` bracket, what would your exit have been?"

The latter matches trading mechanics. If the downstream strategy
will trade with TP/SL brackets, training on TB labels aligns the
model's objective with the realised PnL; training on threshold
labels introduces a systematic mismatch.

See [howto/ml/triple_barrier.md](../../howto/ml/triple_barrier.md)
for the practical A/B workflow.

## Volatility adaptation

Barriers scale with ATR, not fixed percentages. A `1.5 × ATR` TP
is narrow in a quiet market (tight barrier, fast resolution) and
wide in a volatile one (breathing room, slower resolution). The
label's "effective horizon" becomes regime-adaptive: bars in
different volatility regimes are compared on their **relative**
move magnitude, not the absolute one.

Fixed-threshold labelling (`±0.5%`) conflates regimes — 0.5% is a
full session's move in calm days and noise in volatile ones. One
model trained across both regimes has to average over signals
that aren't comparable. TB mitigates that specific failure mode.

## Module layout

A tiny library, one function, one file pair:

```
lib/domain/ml/triple_barrier/
├── dune
├── triple_barrier.mli  — public signature
└── triple_barrier.ml   — ~25 lines, pure arithmetic
```

Signature:

```ocaml
val label :
  arr:Candle.t array ->
  atr:float option array ->
  i:int ->
  tp_mult:float ->
  sl_mult:float ->
  timeout:int ->
  int option
```

ATR is passed in pre-computed — the labeler is deliberately
agnostic to *how* you compute volatility. Callers hand it an
`atr.(i) option` array aligned bar-for-bar with `arr`. This keeps
the labeler's logic a pure walk over candles: no indicator
state, no warmup dance, no tight coupling to `Indicators.Atr`.

The export tool (`bin/export_training_data.ml`) computes ATR
itself in a separate pass (`compute_atr`) using
`Indicators.Atr.make ~period:14` and feeds the result to
`Triple_barrier.label`. If future work wants a different
volatility proxy (e.g. realised-vol over a returns window,
Garman-Klass, Parkinson), the labeler doesn't need to change —
only the ATR-producing pass does.

## Tie-break convention

A single bar whose `[low, high]` range straddles both barriers
simultaneously — gaps, wide-range bars, intraday spikes
compressed into one bar on a daily frame — cannot be resolved
from OHLCV alone. The intra-bar order (did the high or the low
come first?) is not in the data.

**Convention: when in doubt, SL wins.**

```ocaml
if tp_hit && sl_hit then Some 0   (* SL *)
```

Rationale — this is the conservative choice:

- It biases the labeler *against* falsely optimistic "TP" labels.
  An over-optimistic TB-labelled dataset would lead to a model
  that thinks winning setups are more common than they are; the
  resulting overconfident strategy underperforms in practice.
- De Prado's canonical reference uses this convention, so it's
  the default readers of the technique will expect.
- In real trading, such straddling bars are themselves a risk
  signal (the market moved violently in both directions) —
  labelling them pessimistically is defensible.

The alternative (TP-wins tie-break) is sometimes useful for
research purposes — backtesting "best-case" scenarios — but
would produce a training dataset that exaggerates winning
outcomes. Not the default.

## What's NOT included

The TB technique in full de Prado flavour includes several
extensions we haven't implemented. Each is a separate follow-up
if the vanilla version starts paying off:

- **Meta-labelling** — a second classifier trained on the
  first's predictions to filter false positives. Would live as a
  separate two-stage strategy.
- **Dynamic horizons** — scaling `timeout` by ATR just like the
  barriers, so the window stretches with volatility. Currently
  `timeout` is a fixed bar count.
- **Sample weighting by uniqueness** — de Prado notes that
  overlapping labels (bars `i` and `i+1` have partially shared
  forward windows) aren't independent samples and should be
  weighted accordingly during training. Our pipeline treats all
  rows as equal.
- **Fractional-differentiated features** — de Prado also advocates
  stationarity-preserving feature transformations. Orthogonal to
  labelling; a different research direction.

None of these are critical for a first working version. The
labeler as-is is a faithful implementation of the "three
barriers, first-to-trigger" core idea; extensions can slot in
later without changing the interface.

## Integration

Used exclusively by the export tool, gated behind the
`--label-mode triple-barrier` CLI flag. Other modes (threshold)
don't call it.

The output CSV is byte-compatible with threshold mode: same
header, same column order, labels in `[0, 1, 2]`. The Python
training pipeline (`tools/gbt/train.py`) doesn't know or care
which mode produced the data — it sees the same schema.

Strategy-side coherence **is** wired, but not *inside*
`Gbt_strategy`. Brackets are an orthogonal risk-management
overlay that applies to any entry source, so they live in their
own module — `Strategies.Bracket` — a decorator that wraps any
`Strategy.t` and takes over exit decisions once a position is
open. `Gbt_strategy` itself remains pure entry logic: model
class → `Enter_long` / `Enter_short`, no TP/SL state, no ATR
tracking.

The flow under `Bracket(inner = Gbt_strategy)`:

1. On every bar: ATR(14) is updated; the inner strategy is
   stepped so its indicators advance regardless of position.
2. While `Flat`: the inner's signal is propagated. An
   `Enter_long` from the inner, paired with a ready ATR value,
   is enriched with `tp = close + tp_mult × ATR` and
   `sl = close − sl_mult × ATR` in the emitted signal, and the
   decorator transitions to `Long`. Entries during ATR warmup
   are swallowed (Hold) rather than fired naked.
3. While in position: the decorator checks the bar's
   `high` / `low` against frozen barriers. SL before TP (tie
   → SL wins, matching the labeler). After `max_hold_bars`
   without a barrier hit, `Exit_*` fires with reason
   `"timeout"`. The inner's signals are ignored throughout —
   the model learned "which barrier wins within the window",
   not "re-enter on bar 2".
4. After exit, state returns to `Flat` and step 2 applies
   again.

Because the decorator composes via `Strategies.Strategy.t`
(same type as any leaf strategy), it runs identically in
`Backtest.run`, in the `Live_engine` with `Paper_broker`, and
in live execution through any real broker (BCS, Finam, future
additions). No changes to `Live_engine`, `Paper`, or broker
ACLs are required — the decorator emits `Exit_long` /
`Exit_short` as needed, and downstream just executes them as
regular market orders. No native broker bracket support is
assumed or required.

The registry exposes the paired product as `Bracket_GBT` —
callers who want brackets pick it; callers who want bare GBT
predictions (e.g. for training-diagnostic backtests without
risk rules) pick `GBT`. Bracket is not GBT-specific; the same
decorator can wrap any `Strategy.t`, which is the point of
keeping it separate.

If a future broker offers native bracket orders (BCS and Finam
currently don't), those would slot in as a **safety net**: the
decorator's engine-side brackets remain the primary control,
and a server-side TP/SL order is attached in parallel to
protect against engine crashes or WS disconnects. Orthogonal,
additive — doesn't change the primary architecture.

## Testing

Nine unit tests in
[`test/unit/domain/ml/triple_barrier/triple_barrier_test.ml`](../../../test/unit/domain/ml/triple_barrier/triple_barrier_test.ml):

- TP hit first, SL hit first, timeout (the three happy paths)
- Both barriers hit same bar → SL-wins tie-break
- Anchor bar `[i]` itself doesn't count (walk starts at `i+1`)
- ATR warm-up: `None` ATR → `None` label
- Zero ATR rejected (degenerate barriers)
- Asymmetric barriers (`tp_mult ≠ sl_mult`)
- Partial tail window when `i + timeout` exceeds array length

Tests construct tiny candle arrays with deliberately set
high/low paths — the candles are synthetic, not from live data,
because the point is to verify the walker's decision logic in
isolation.
