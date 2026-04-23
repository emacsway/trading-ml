# How to run an A/B comparison: threshold vs triple-barrier labels

Does triple-barrier labelling actually help for this instrument,
this timeframe, this feature set? The only honest way to know
is to train both and compare.

For background on the technique itself see
[architecture/ml/triple_barrier.md](../../architecture/ml/triple_barrier.md).
This document assumes you've read it.

## The workflow

Pick one instrument and a reasonable history window (1-2 years
of hourly bars is plenty). Export two CSVs — same bars, same
features, different labels — then train two models and compare
walk-forward CV accuracy side by side.

### Step 1 — Export both label variants

```bash
# Threshold baseline
dune exec -- bin/export_training_data.exe -- \
  --broker finam \
  --symbol SBER@MISX \
  --timeframe H1 \
  --from 2024-01-01 \
  --to 2026-04-20 \
  --label-mode threshold \
  --horizon 5 \
  --threshold 0.005 \
  --output /tmp/sber_threshold.csv

# Triple-barrier
dune exec -- bin/export_training_data.exe -- \
  --broker finam \
  --symbol SBER@MISX \
  --timeframe H1 \
  --from 2024-01-01 \
  --to 2026-04-20 \
  --label-mode triple-barrier \
  --tp-mult 1.5 \
  --sl-mult 1.0 \
  --timeout 20 \
  --output /tmp/sber_triple_barrier.csv
```

The triple-barrier run will print a class distribution line on
stdout:

```
Triple-barrier class distribution: 0(down)=1420 1(flat)=892 2(up)=1305
```

Glance at this. You want something roughly balanced. Very skewed
distributions (one class `> 60%`) usually mean the barrier
multipliers are mismatched to the instrument's typical move
range; see "Tuning the barriers" below.

### Step 2 — Train both

```bash
source ~/.venvs/trading-ml/bin/activate

python tools/gbt/train.py \
  --input  /tmp/sber_threshold.csv \
  --output /tmp/sber_threshold_v1.txt \
  --seed 42

python tools/gbt/train.py \
  --input  /tmp/sber_triple_barrier.csv \
  --output /tmp/sber_triple_barrier_v1.txt \
  --seed 42
```

Same `--seed` across both runs means the `TimeSeriesSplit` fold
boundaries are deterministic and numerically identical between
the two — any accuracy difference is attributable to labels, not
to random fold shuffling.

### Step 3 — Compare

For each model, the trainer prints mean CV accuracy and lift over
baseline. Compare side by side:

```
              mean acc    std     lift vs 0.333 baseline
threshold:    0.4118    ±0.0066    +7.85 pp
triple-bar:   0.4341    ±0.0051    +10.08 pp
```

Also inspect the sidecar JSON for per-fold detail:

```bash
diff <(jq '.cv' /tmp/sber_threshold_v1.meta.json) \
     <(jq '.cv' /tmp/sber_triple_barrier_v1.meta.json)
```

Feature importance often shifts noticeably. TB labels tend to
emphasise volatility/volume features (`bb_pct_b`, `volume_ratio`,
`chaikin_osc`) because path-dependent outcomes are more sensitive
to intra-window excursions than raw return direction.

### Step 4 — Decide

Interpret the outcome against three thresholds:

| Triple-barrier lift over threshold | Meaning |
|---|---|
| `> +2 pp` with lower std | Clear signal, proceed to phase 2 (bracket-trading strategy) |
| `+0.5 to +2 pp` | Marginal, re-test with different barrier configs before investing in phase 2 |
| `≤ ±0.5 pp` | No practical difference; threshold is simpler, keep it |
| `< −0.5 pp` | TB performs worse — barrier multipliers are badly picked, or your features don't capture path-sensitive info |

A single comparison isn't conclusive — do at least three runs
with different random seeds (`--seed 42 | 43 | 44`) and average.
If the delta is consistent across seeds, trust it.

## Tuning the barriers

The three TB hyperparameters — `tp_mult`, `sl_mult`, `timeout`
— determine everything. Bad defaults kill the experiment before
it starts.

### Class distribution as sanity

The easiest sanity check is the distribution printed at the end
of export. Rough guidelines for a balanced dataset:

- Roughly equal classes (each ~25-40%): barriers are well-matched
  to the instrument's typical movement within `timeout`.
- `1 (flat)` dominates (> 60%): barriers are too wide — widen
  timeout or tighten multipliers (`tp_mult 1.5 → 1.0`).
- `1 (flat)` rare (< 10%): barriers are too tight; most bars
  touch one quickly. Widen them or shorten timeout.
- `0 (down)` vastly outweighs `2 (up)` (or vice versa): the
  market was trending during your window. Either expand the
  history or accept the imbalance and rely on walk-forward CV to
  expose non-stationarity.

### Reasoning about multipliers

For equities at hourly frequency, `tp_mult = 1.5`, `sl_mult =
1.0` is a reasonable starting point — asymmetric because a 1:1.5
payoff ratio matches the small-but-positive edge you'd expect
from mean-reversion-ish models.

If the strategy you're eventually planning is momentum-oriented,
consider the reverse: `tp_mult = 1.0`, `sl_mult = 0.5` (tight
stop, quick take) — reflects "many small winners, few large
losses" typical of momentum.

Honestly though, barrier-tuning is also an overfitting risk. If
you tune multipliers on one period and accuracy goes up, then
hold out another period and it doesn't — you tuned, not
discovered. The discipline is:

1. Pick sensible defaults (1.5 / 1.0 / 20) based on literature
   and instrument heuristics.
2. Train. Measure.
3. **Do not** loop "tweak multipliers until accuracy goes up" on
   the same period. That's `grad(valid_accuracy)` cheating.
4. If defaults work, keep them. If they don't, try two or three
   principled alternatives, pick the best, move on.

### `timeout` reasoning

`timeout = 20` on H1 bars means the label summarises whether a
bracket would have resolved within 20 hours (~a couple of
trading sessions). Align with what your live strategy would do:

- Intraday: `timeout` = bars-per-session (usually 7-8 on H1).
- Swing (multi-day): `timeout = 20-40`.
- Position (weeks): `timeout = 100+`.

Longer timeouts give more time for path-dependent paths to
resolve, but make the dataset tail shrink (fewer valid rows
because you need `N - timeout` usable anchors).

## Caveats and pitfalls

### You're still looking at accuracy, not PnL

A TB-label model predicts "would the bracket trade have won?",
but the actual PnL depends on executed TP/SL levels, slippage,
and commission. Accuracy improvements don't translate 1:1 to
returns.

For a proper read, measure simulated PnL of the TB strategy on
the test fold: treat every class-`2` prediction as a trade with
the exact `tp_mult` / `sl_mult` / `timeout` used for labelling,
sum up realised outcomes. Our current Paper broker can
approximate this if you wire the strategy to emit brackets (the
phase-2 work referenced in the TB architecture doc).

### Overlap bias

Two consecutive bars' TB labels look at overlapping forward
windows. Bars `t` and `t+1` both care about bars `[t+1, t+20]`
and `[t+2, t+21]` respectively — 19 bars shared. The ML training
treats these as independent samples, which they aren't.
De Prado's book recommends uniqueness-weighting; we don't do it.
Effect in practice: mildly inflated accuracy (model "learns" the
same path twice). A 1 pp CV lift in TB mode might shrink to
0.5 pp with proper weighting.

Not a deal-breaker for first-pass experiments, worth keeping in
mind if you'll make a deployment decision on borderline lift
numbers.

### Label imbalance and metrics

`argmax` accuracy is fine when classes are balanced. If your TB
distribution is heavily skewed (`60% down / 10% flat / 30% up`),
simple accuracy can be misleading — a model that always predicts
`down` gets 60% "for free". Use per-class precision/recall and
balanced accuracy from `tools/gbt/evaluate.py` alongside the raw
accuracy number when interpreting.

## If the result is positive

Good news: strategy-side coherence is already wired. `Gbt_strategy`
implements brackets in its own FSM and honours them identically
in backtest, paper, and live paths. When you deploy a TB-trained
model in production:

1. Make sure `tp_mult` / `sl_mult` / `max_hold_bars` on the
   strategy match the ones used at labelling time. The registry
   defaults already align (1.5 / 1.0 / 20), but if you trained
   with non-default values, pass them explicitly:
   ```bash
   dune exec -- trading serve --broker bcs --strategy GBT \
     --param model_path=/path/to/model.txt \
     --param tp_mult=2.0 --param sl_mult=1.0 --param max_hold_bars=30
   ```
2. Verify the sidecar `.meta.json` if you're deploying weeks
   later — training-time CV accuracy there should match what
   `evaluate.py` reports on recent data; serious drift is the
   signal to retrain.

See the `Strategy-side coherence` section in
[`architecture/ml/triple_barrier.md`](../../architecture/ml/triple_barrier.md)
for the design rationale and why the brackets live in the
strategy (not the engine, not the broker).
