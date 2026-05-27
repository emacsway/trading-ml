#!/usr/bin/env python3
"""Empirically validate that Alor's public-tape ``side`` is the AGGRESSOR side.

This closes the "to watch for" caveat of ADR 0032: the whole footprint
delta pyramid rests on the assumption that a public trade's ``side``
marks the initiator that crossed the spread (a Buy lifted the ask, a
Sell hit the bid) — not the resting limit order, and not something
unrelated. If the venue reports the opposite side, every delta-based
signal is inverted.

Method (broker-agnostic in spirit; this file targets Alor):

  1. Subscribe to the instrument's L1 quotes (QuotesSubscribe) and keep
     the latest best bid / best ask.
  2. Subscribe to all public trades (AllTradesGetAndSubscribe).
  3. For each trade, classify the aggressor by the quote rule:
       price >= best_ask  -> Buy  aggressor (lifted the ask)
       price <= best_bid  -> Sell aggressor (hit the bid)
       strictly inside    -> ambiguous (cannot decide from L1 alone)
  4. Compare that to the venue-reported ``side`` and tally agreement.

Verdict over the *classifiable* trades (known quote, not inside spread):
  agreement ~100%  -> side == aggressor  (CONFIRMED — model is correct)
  agreement   ~0%  -> side == resting    (INVERTED — flip before live!)
  agreement  ~50%  -> side is unrelated to the quote rule (investigate)

Caveats:
  - Quote/trade interleaving on the wire is racy; a single trade may be
    matched against a quote that is a few ms stale. This is why the
    verdict is statistical over many trades, not per-trade.
  - Run during MOEX continuous trading on a LIQUID instrument, where the
    spread is one tick and ambiguity is minimal.

Prerequisites:
  pip install AlorPy
  export ALOR_REFRESH_TOKEN=<your Alor OAuth refresh token>

Usage:
  python validate_alor.py [DATANAME] [SECONDS]
  e.g. python validate_alor.py TQBR.SBER 180
"""

import os
import sys
import time
from collections import Counter

try:
    from AlorPy import AlorPy  # type: ignore  # pip install AlorPy
except ImportError:
    sys.exit("AlorPy is not installed. Run: pip install AlorPy")


def main() -> int:
    dataname = sys.argv[1] if len(sys.argv) > 1 else "TQBR.SBER"
    seconds = int(sys.argv[2]) if len(sys.argv) > 2 else 120

    token = os.environ.get("ALOR_REFRESH_TOKEN")
    if not token:
        sys.exit("Set ALOR_REFRESH_TOKEN to your Alor OAuth refresh token.")

    provider = AlorPy(refresh_token=token)
    board, symbol = provider.dataname_to_alor_board_symbol(dataname)
    exchange = provider.get_exchange(board, symbol)

    # Latest L1 top of book. Updated by the quote stream, read by the
    # trade stream. Single-threaded callbacks on AlorPy's WS thread, so
    # no locking is needed.
    book: dict[str, float | None] = {"bid": None, "ask": None}
    counts = Counter()
    disagreements = []  # a few examples for eyeballing
    first_quote_logged = False

    def on_quote(response):
        nonlocal first_quote_logged
        data = response["data"]
        if not first_quote_logged:
            print(f"[debug] first quote payload: {data}")
            first_quote_logged = True
        # Alor QuotesSubscribe (Simple) carries best bid/ask as 'bid'/'ask'.
        # If your payload differs, adjust these two keys.
        if data.get("bid") is not None:
            book["bid"] = float(data["bid"])
        if data.get("ask") is not None:
            book["ask"] = float(data["ask"])

    def on_trade(response):
        data = response["data"]
        if data.get("existing"):  # historical backfill, not a live print
            return
        counts["trades"] += 1
        side = str(data.get("side", "")).lower()  # 'buy' | 'sell'
        price = float(data["price"])
        bid, ask = book["bid"], book["ask"]
        if bid is None or ask is None:
            counts["no_quote_yet"] += 1
            return
        if price >= ask:
            aggressor = "buy"
        elif price <= bid:
            aggressor = "sell"
        else:
            counts["ambiguous_inside_spread"] += 1
            return
        counts["classifiable"] += 1
        if side == aggressor:
            counts["agree"] += 1
        else:
            counts["disagree"] += 1
            if len(disagreements) < 10:
                disagreements.append(
                    f"price={price} bid={bid} ask={ask} "
                    f"reported_side={side} quote_rule={aggressor}"
                )

    provider.on_new_quotes.subscribe(on_quote)
    provider.on_all_trades.subscribe(on_trade)
    provider.quotes_subscribe(exchange, symbol)
    provider.all_trades_subscribe(exchange, symbol, depth=0)

    print(f"Listening to {dataname} for {seconds}s — run during MOEX hours...")
    try:
        time.sleep(seconds)
    except KeyboardInterrupt:
        pass
    finally:
        provider.close_web_socket()

    report(dataname, counts, disagreements)
    return 0


def report(dataname, counts, disagreements) -> None:
    classifiable = counts["classifiable"]
    agree = counts["agree"]
    print("\n" + "=" * 64)
    print(f"Aggressor-side validation — {dataname}")
    print("=" * 64)
    print(f"trades observed          : {counts['trades']}")
    print(f"  no quote yet           : {counts['no_quote_yet']}")
    print(f"  ambiguous (in spread)  : {counts['ambiguous_inside_spread']}")
    print(f"  classifiable           : {classifiable}")
    print(f"    agree (side=aggr)    : {agree}")
    print(f"    disagree             : {counts['disagree']}")
    if classifiable == 0:
        print("\nVERDICT: inconclusive — no classifiable trades (market closed,"
              " illiquid, or wrong quote field names).")
        return
    rate = agree / classifiable
    print(f"\nagreement rate           : {rate:.1%}")
    if rate >= 0.95:
        verdict = ("CONFIRMED: side == aggressor. The footprint delta model "
                   "is correct as built.")
    elif rate <= 0.05:
        verdict = ("INVERTED: side == resting/opposite. FLIP the mapping in "
                   "the ACL before going live — every delta signal is reversed.")
    else:
        verdict = ("UNRELATED: side does not track the quote rule. Investigate "
                   "the venue's side semantics before building the relay.")
    print(f"VERDICT: {verdict}")
    if disagreements:
        print("\nsample disagreements:")
        for d in disagreements:
            print(f"  {d}")


if __name__ == "__main__":
    raise SystemExit(main())
