# How to train and deploy a logistic gate

End-to-end walkthrough: take a set of existing heuristic
strategies (SMA crossover, RSI mean reversion, etc.), learn a
logistic classifier that decides **when to trust their
consensus**, and deploy the result as a `Composite.Learned`
policy.

For design background see
[architecture/ml/logistic_regression.md](../../architecture/ml/logistic_regression.md).
This document assumes you've read it and focuses on the
mechanics.

The logistic pipeline is dramatically smaller than the
[GBT one](gbt.md): training happens in-process in OCaml, weights
are ~10 scalars, no Python, no `.meta.json` sidecar, no
hot-reload watcher. The whole loop — "construct children, fit,
use" — is a dozen lines of OCaml.

## What you're actually training

A common misconception: "logistic regression replaces my heuristic
strategies with an ML model". It doesn't. Its job is to **gate**
their signals — given that SMA Crossover, RSI Mean Reversion,
MACD Momentum and Bollinger Breakout all emit their opinions on
a bar, logistic decides whether their collective opinion is
reliable *right now* (given the market regime).

Concretely the input features are:

- `(signal, strength)` pair from each child strategy
- `volatility` (coefficient of variation of recent closes)
- `volume_ratio` (current volume / mean of recent volumes)

The output is `P(profitable)`: probability that entering long on
the next bar yields a positive return over the lookahead window.
`Composite.Learned` treats this as `Enter_long if P > threshold,
else Hold`.

The rule logistic can learn — and that plain `Adaptive` /
`Majority` policies cannot — is **regime-conditional trust**:
"children collectively work in low-volatility periods but
misfire when vol spikes". Whether that rule is actually present
in your data is the empirical question the trainer answers.

## Prerequisites

None outside the OCaml build. No Python, no venv. The training
is a dedicated binary built together with the rest of the
project — `dune build` produces `_build/default/bin/train_logistic.exe`.

Broker credentials are resolved the same way as for other
binaries (see `trading --help` for full list): `--secret` /
`--account` / `--client-id` flags or the matching
`<BROKER>_SECRET` / `<BROKER>_ACCOUNT_ID` / `BCS_CLIENT_ID`
env vars.

## Train: one command

```bash
dune exec -- bin/train_logistic.exe -- \
  --broker finam \
  --symbol SBER@MISX \
  --timeframe H1 \
  --from 2024-01-01 \
  --to 2026-04-20 \
  --children SMA_Crossover,RSI_MeanReversion,MACD_Momentum,Bollinger_Breakout \
  --lookahead 5 \
  --epochs 10 \
  --output ~/.local/state/trading/models/sber_h1_logistic.json
```

The tool paginates historical bars across the date window (same
walker as `export_training_data.exe`), runs the comma-separated
list of child strategies through them, fits a logistic
classifier in-process, and writes the weights as JSON.

Typical output (numbers vary with data):

```
Fetched 5043 bars from finam (SBER@MISX)
Children (4): SMA_Crossover, RSI_MeanReversion, MACD_Momentum, Bollinger_Breakout
Trained: n_train=1342 n_val=575 train_loss=0.6782 val_loss=0.6891
Wrote /home/user/.local/state/trading/models/sber_h1_logistic.json (11 weights)
```

### Options

| Flag | Default | Meaning |
|---|---|---|
| `--broker` | required | `finam` or `bcs` |
| `--symbol` | required | Qualified `TICKER@MIC[/BOARD]` |
| `--output` | required | JSON file to write |
| `--children` | required | Comma-separated registry names |
| `--timeframe` | `H1` | `M1 \| M5 \| M15 \| M30 \| H1 \| H4 \| D1` |
| `--from` / `--to` | last 365 days | ISO date or full RFC 3339 |
| `--lookahead` | 5 | Bars to label forward for `P(profitable)` |
| `--epochs` | 10 | SGD passes over the training split |
| `--lr` | 0.01 | Learning rate |
| `--l2` | 1e-4 | L2 weight-decay coefficient |
| `--context-window` | 20 | Recent bars for volatility / volume_ratio features |

### Child-order invariant

The feature vector is positional: the weight at index `2·i`
pairs with the `i`-th child's signal. **Retraining with a
different child list produces a new weights file that's
incompatible with the old live config** — every weights file is
tied to the exact children passed at training time.

Document the children list alongside the weights file (e.g. in a
sibling `sber_h1_logistic.children` text file, or as a comment
in deployment YAML); the binary itself doesn't round-trip that
metadata into the JSON — weight files are just `{ weights, lr,
l2 }`.

## Interpreting the result

- **`n_train` / `n_val`** — how many bars contributed a labelled
  example. Bars where every child said `Hold` are skipped
  (nothing to learn from); bars inside the last `lookahead`
  slice are skipped too (no ground truth yet). A low count
  (`n_train < 100`) means the trainer couldn't find enough
  decision points — increase history, pick more active children,
  or shorten `lookahead`.

- **`train_loss` / `val_loss`** — cross-entropy log-loss.
  Baseline for a 2-class problem is `ln 2 ≈ 0.693` (a model
  that always predicts 0.5). Val loss significantly below 0.69
  is signal; val loss > train loss by more than a few percent
  is overfitting (bump `l2`, drop `epochs`).

- **Weights** — first scalar is bias, rest are per-feature. The
  feature layout is documented in
  [architecture/ml/logistic_regression.md](../../architecture/ml/logistic_regression.md#feature-vector):
  interleaved `(signal, strength)` per child, followed by
  `volatility` and `volume_ratio`. A large positive weight on
  `signal₁` means "trust child 1"; a large negative weight on
  `volatility` means "distrust everything when vol is high".

## Deploying the trained gate

Load the trained model at startup via `Logistic.of_file`, wrap
`Features.extract` + `Logistic.predict` into a closure matching
`Composite.predictor`, and hand the whole thing to a
`Composite.Learned` strategy:

```ocaml
let logistic = Logistic_regression.Logistic.of_file
  "/home/user/.local/state/trading/models/sber_h1_logistic.json" in

let predict ~signals ~candle ~recent_closes ~recent_volumes =
  let features = Logistic_regression.Features.extract
    ~signals ~candle ~recent_closes ~recent_volumes in
  Logistic_regression.Logistic.predict logistic features

let composite = Strategies.Strategy.make (module Strategies.Composite)
  Strategies.Composite.{
    policy = Learned { predict; threshold = 0.55 };
    children = [
      Strategies.Strategy.default (module Strategies.Sma_crossover);
      Strategies.Strategy.default (module Strategies.Rsi_mean_reversion);
      Strategies.Strategy.default (module Strategies.Macd_momentum);
      Strategies.Strategy.default (module Strategies.Bollinger_breakout);
    ];
  }
```

**Invariant: the child list here must match the child list passed
to the trainer, in the same order.** The weights index into the
feature vector positionally, and a reorder silently corrupts
predictions. If you add a child, retrain from scratch — the
weight vector's length changes.

Feed the resulting `composite` into `Backtest.run` or a
`Live_engine.config` exactly like any other strategy. Nothing
downstream cares that it's ML-backed.

## Persistence

`Logistic.to_file` / `Logistic.of_file` read and write a small
JSON envelope carrying weights plus learning hyperparameters:

```json
{
  "weights": [ 0.023451, -0.158234, 0.087621, ... ],
  "lr":      0.01,
  "l2":      0.0001
}
```

Writes go through a tmp-file + atomic rename (same pattern as
`Token_store.file.save`), so a running process reading the file
never sees a half-written state. Unknown fields are ignored, and
missing `lr`/`l2` fall back to the `Logistic.make` defaults — so
hand-written fixtures can get away with `{ "weights": [...] }`.

No hot-reload machinery like GBT's `mtime`-watch — the weights
are read once at startup. If you retrain and want the new
weights in production, restart the process. For a 10-scalar
vector, that's a reasonable trade-off; if weights live in a
config file and change often, add your own reload hook.

## Retraining

Since the whole pipeline is one binary invocation, the retrain
loop is a small shell script — no intermediate files to stage,
no Python environment to activate:

```bash
#!/bin/bash
set -euo pipefail

TODAY=$(date -u +%Y-%m-%d)
FROM=$(date -u -d '2 years ago' +%Y-%m-%d)
MODEL_DIR="$HOME/.local/state/trading/models"
mkdir -p "$MODEL_DIR"

dune exec -- bin/train_logistic.exe -- \
  --broker finam \
  --symbol SBER@MISX \
  --from "$FROM" --to "$TODAY" \
  --children SMA_Crossover,RSI_MeanReversion,MACD_Momentum,Bollinger_Breakout \
  --output "$MODEL_DIR/sber_h1_logistic_$TODAY.json"

ln -sf "$MODEL_DIR/sber_h1_logistic_$TODAY.json" \
       "$MODEL_DIR/sber_h1_logistic_current.json"
```

The engine reads the target once at startup via
`Logistic.of_file`, so picking up a fresh model still needs a
process restart. For logistic's ~10-scalar vectors that's
noise; if it ever matters, the same `mtime`-watch pattern as
`Gbt_strategy` could be added.

## Troubleshooting

### `val_loss == Float.infinity`

The dataset had fewer than 10 labelled rows. See the
`n_total < 10` branch in
[`trainer.ml`](../../../lib/domain/ml/logistic_regression/trainer.ml).
Causes:

- Too few candles (tens instead of hundreds)
- Every child Hold'ed every bar (child params too conservative,
  or strategies genuinely silent on the period)
- Lookahead too large (tail bars dropped exhaust the dataset)

### `val_loss > train_loss + 0.05` — overfitting

- Raise `l2` (try 1e-3 or 1e-2)
- Drop `epochs` (try 3-5 instead of 10)
- More data, especially held-out

### `val_loss ≈ train_loss ≈ 0.693` — not learning

Baseline log-loss for coin-flip prediction. The classifier
can't beat random. Options:

- The signal genuinely isn't there — try different children,
  different lookahead, different instrument.
- Learning rate too high, oscillating. Drop `lr` to 0.001.
- Feature scaling — all features are in similar ranges by
  design (`[-1, 1]` for signals, `[0, 1]` for strengths,
  `[0, ∞)` for volatility/volume_ratio), but extreme volume
  spikes could swamp the others. Consider clipping.

### Weights have NaN / inf

`lr` too high caused a gradient explosion, or `candles` has NaN
prices somewhere upstream. Inspect `candles` first; if clean,
drop `lr` by 10×.

## Compared to GBT

The GBT pipeline is heavier because the trade-off is different:

- GBT learns richer non-linear interactions and gives
  standalone class predictions (direct up/flat/down signals,
  not a gate).
- Logistic learns a linear combination of child signals — less
  expressive, but trains in seconds, fits in 10 numbers, and
  doesn't need Python.

If you have strong heuristic children already and want to combine
them smarter, start with logistic. If you want the model to
**replace** the heuristics and discover patterns from raw
indicators, go to [GBT](gbt.md).
