# How to backtest a footprint strategy and record a live tape

Footprint (order-flow) analysis needs a **tape** — the stream of
individual trades with their aggressor side — not just OHLCV bars. This
guide shows the three things you will actually do: run a footprint
backtest on a synthetic tape, record a real tape from a live venue, and
replay that recorded tape offline. For the design behind the feature
see [order-flow.md](../architecture/order-flow.md) and
[ADR 0032](../adr/0032-order-flow-bounded-context.md).

## 1. Backtest on a synthetic tape (no network, no credentials)

The default backtest path generates a synthetic tape: each candle is
expanded into prints that reconstruct its OHLC, published on
`broker.trade-printed`, so the whole footprint loop
(`order_flow → footprint-completed → strategy`) runs offline.

```bash
dune exec bin/main.exe -- backtest FootprintCVDDivergence --n 300 --symbol SBER@MISX
```

Output (the `footprint=` count is the footprint-sourced signals,
broken out of the total):

```
backtest: strategy=FootprintCVDDivergence symbol=SBER@MISX candles=300
  signals_emitted=17 (footprint=17)
  intents: planned=… approved=… rejected=…
  reservations: ok=… rejected=…
  orders: accepted=… rejected=… unreachable=…
  submissions_blocked=…
```

Flags:

| Flag | Meaning | Default |
|------|---------|---------|
| `--n` | number of candles to generate | `200` |
| `--symbol` | instrument (`TICKER@MIC`) | `SBER@MISX` |
| `--tape FILE` | replay a recorded tape instead of generating one (§3) | — |

> **What this proves.** The synthetic delta is *generated*, so a
> synthetic backtest validates footprint **mechanics** — that prints
> are partitioned into bars, classified by aggressor, conserved, and
> turned into signals — **not** microstructure **alpha**. For the
> latter you need a real recorded tape (§2–§3).

## 2. Record a real tape from a live venue

Each broker's live-smoke probe doubles as a tape recorder: pass
`--record FILE` and every relayed print is written as one
`Trade_printed` JSON per line — the exact wire shape the backtest
replays. Probes are **opt-in** (not part of `@runtest`) and skip
cleanly when their credential env var is absent. Run during MOEX
continuous trading so the tape actually flows.

**Finam** (confirmed aggressor semantics, 2026-05-27):

```bash
export FINAM_SECRET=<portal secret>
dune exec broker/test/live_smoke/finam_public_trades_probe.exe -- --record /tmp/sber.tape
```

**BCS** (relay built; run this to confirm the LastTrades frame shape
and side encoding before trusting its delta):

```bash
export BCS_SECRET=<keycloak refresh token>
dune exec broker/test/live_smoke/bcs_public_trades_probe.exe -- --record /tmp/sber-bcs.tape
```

Besides recording, each probe prints a per-print **aggressor verdict**
against the L1 quote (BUY at ask / SELL at bid ⇒ `side` is the
aggressor; the reverse ⇒ the mapping is inverted and `parse_side` must
flip). The BCS probe also dumps the first raw frames of each channel,
since the BCS tape frame shape is inferred rather than documented — if
a field differs, the dump shows the truth and parser + fixtures move
together. A run ends with a summary verdict:

```
VERDICT among L1-classifiable prints: agree=N  INVERTED=0  (ambiguous=…, no_quote=…)
=> side == aggressor CONFIRMED: of_domain mapping is correct.
```

## 3. Replay a recorded tape offline

Feed the recorded file back through the same backtest composition with
`--tape`. Replay reads the tape verbatim (blank lines and
unparseable lines are skipped) and drives the footprint loop from real
prints instead of synthetic ones:

```bash
dune exec bin/main.exe -- backtest FootprintCVDDivergence --tape /tmp/sber.tape --symbol SBER@MISX
```

The summary line is identical to §1; now the `footprint=` signals are
derived from genuine aggressor data, so the run reflects real
microstructure.

## 4. Running it live

In a live (or paper) deployment the loop is always on — the trading
host builds the `order_flow` factory, the broker subscribes the public
tape for each watchlist instrument, and the strategy BC runs the
`FootprintCVDDivergence` engine. There is nothing extra to enable; pick
the venue with `--broker` and supply its credentials:

```bash
dune exec bin/main.exe -- serve --broker finam --secret <…>   # or --broker bcs / alor
```

## Troubleshooting

- **`footprint=0` on a synthetic backtest.** Expected for very small
  `--n` or a flat generated series; increase `--n`. Divergence needs
  enough history to fill the lookback window.
- **Probe prints `[SKIP] … not set`.** The credential env var
  (`FINAM_SECRET` / `BCS_SECRET`) is absent — export it and re-run.
- **Probe verdict `inconclusive` / `no_quote` high.** The market was
  thin or quotes lagged trades; widen the window (re-run during active
  trading). For BCS specifically, read the raw QUOTE dump — if no
  bid/ask is recoverable, the L1 field names need confirming before the
  verdict means anything.
- **`backtest --tape` reports fewer prints than the file has lines.**
  Malformed or blank lines are skipped silently by design; check the
  file was written by a probe's `--record`, not hand-edited.

## See also

- [Order flow — architecture](../architecture/order-flow.md).
- [ADR 0032](../adr/0032-order-flow-bounded-context.md) — the decision
  record, including the tick-replay rationale and the
  synthetic-vs-recorded caveat.
