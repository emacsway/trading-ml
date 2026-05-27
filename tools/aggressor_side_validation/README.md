# Aggressor-side validation

A diagnostic probe, not part of any bounded context. It empirically
checks the assumption the whole footprint delta model rests on (ADR
0032, "to watch for"): that a public trade's `side` reported by a venue
marks the **aggressor** — the order that crossed the spread — and not
the resting limit order or something unrelated.

If the venue reports the opposite side, every delta-based signal built
on top of the `order_flow` BC would be inverted. This must be confirmed
against live data before the broker trade relay is built.

## Why a script the operator runs, not an automated test

The check needs a live tick stream during exchange hours and the
operator's broker credentials. It cannot run in CI or offline. The
script subscribes to the public tape and the L1 quote stream, keeps the
latest best bid/ask, classifies each trade by the quote rule
(`price ≥ ask` → buy aggressor, `price ≤ bid` → sell aggressor), and
compares that to the venue-reported `side`, then prints an aggregate
verdict.

## Alor

```sh
pip install AlorPy
export ALOR_REFRESH_TOKEN=<your Alor OAuth refresh token>
python validate_alor.py TQBR.SBER 180
```

Run during MOEX continuous trading (10:00–18:40 MSK on the main board)
on a liquid instrument, where the spread is typically one tick and
ambiguity is minimal.

### Reading the verdict

Over the *classifiable* trades (a quote was known and the price was not
strictly inside the spread):

| agreement rate | meaning | action |
|---|---|---|
| ~100% | `side` == aggressor | model is correct; proceed to build the relay |
| ~0%   | `side` == resting/opposite | **flip** the mapping in the ACL before going live |
| ~50%  | `side` unrelated to the quote rule | investigate the venue's semantics |

The script prints a few sample disagreements so the boundary cases can
be eyeballed.

## Caveats

- Quote/trade interleaving on the wire is racy: a trade may be matched
  against a quote a few milliseconds stale. The verdict is therefore
  statistical over many trades, never per-trade.
- Auction and negotiated prints have no aggressor; on Alor they surface
  as ordinary `buy`/`sell` with no flag, so they may add noise around
  the open/close auctions. Prefer a mid-session window.
- BCS and Finam can be validated the same way (BCS: `dataType:2` trades
  + `dataType:3` quotes; Finam: `INSTRUMENT_TRADES` + `QUOTES`). Add a
  sibling script when those credentials are available.
