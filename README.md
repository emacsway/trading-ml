# Trading — OCaml algo-trading system with Finam Trade

Functional algorithmic-trading platform in OCaml. Strategies and indicators
are first-class, hot-swappable, each lives in its own file, and all critical
bookkeeping (decimal math, portfolio, candle invariants) is specified with
[Gospel](https://github.com/ocaml-gospel/gospel) for formal verification.

## Layout

    lib/
      core/            Decimal, Symbol, Timeframe, Candle, Side, Order, Signal
      indicators/      Indicator framework + SMA, EMA, RSI, MACD, Bollinger, ATR
      strategies/      Strategy framework + SMA crossover, RSI MR, MACD, Bollinger
      engine/          Portfolio, Risk, Backtester
      finam/           Finam Trade connector (REST, WebSocket, DTO)
      server/          HTTP API exposing data/backtests to the UI
    bin/               CLI entry point
    test/              Alcotest + QCheck unit & property tests
    ui/                Angular application (candles + indicator overlays)

## Build & test

    opam install . --deps-only --with-test      # one-off
    dune build
    dune runtest                                # 20 tests

Verify Gospel specifications on the critical `.mli` files:

    gospel check lib/core/decimal.mli
    gospel check lib/core/candle.mli

Specifications carried today:

| File                   | Spec kind                                                    |
| ---------------------- | ------------------------------------------------------------ |
| `lib/core/decimal.mli` | `div` raises `Division_by_zero` spec                         |
| `lib/core/candle.mli`  | `make` invariants: `low ≤ open,close ≤ high`, `volume ≥ 0`   |
| `lib/engine/portfolio.mli` | `fill` preconditions (quantity > 0, fee ≥ 0) — documented |

The portfolio `.mli` uses the cross-library type `Core.Symbol.t`; Gospel's
load-path resolution for dune-wrapped libraries is limited, so the
specifications there are documentation-grade rather than machine-checked.
JSON encodings live in `*_json.ml` companion files to keep the verified
`.mli` free of Yojson dependencies.

## Run

    dune exec -- bin/main.exe list
    dune exec -- bin/main.exe backtest SMA_Crossover --n 500
    dune exec -- bin/main.exe serve --port 8080

Then, from another terminal:

    cd ui && npm install && npm start
    # open http://localhost:4200

The UI targets Angular 21 with zoneless change detection, signals-based
reactivity, the `@if` / `@for` control flow, and `input()`/`output()`
component APIs. `lightweight-charts` v5 draws the candlesticks.

UI unit tests run under Vitest (Angular 21's default) with `jsdom`:

    cd ui && npm test

The suite covers:

- `indicators.spec.ts` — SMA / EMA / Bollinger math (invariants, edge cases,
  regime-change behaviour, catastrophic-cancellation guard).
- `api.service.spec.ts` — HTTP surface via `HttpTestingController`.
- `app.component.spec.ts` — signal-driven reactivity: catalog seeding, toggling
  indicators, reloading candles on symbol change, backtest result storage.

## Adding a new indicator

Create `lib/indicators/my_ind.ml`, implement `Indicator.S`, register in
`lib/indicators/registry.ml`. The UI picks it up automatically.

## Adding a new strategy

Create `lib/strategies/my_strategy.ml`, expose the `name`, `params`,
`state`, `default_params`, `init`, `on_candle` bindings (matching
`Strategy.S`), register in `lib/strategies/registry.ml`.

## Finam connector

The REST client in `lib/finam/rest.ml` is structured around a pluggable
`Transport.t`, so it is easy to unit-test with a fake and to wire to any
TLS-capable backend in production. Set your token and account via
`Finam.Config.make ~access_token ~account_id ()`.

The WebSocket layer in `lib/finam/ws.ml` defines the subscription protocol
and event decoder as pure values; glue it to your preferred WS transport
(e.g. `ocaml-websocket`, `h2`, or a home-grown Eio frame reader).
