(** Inbound command to the Portfolio Management BC: "advance every
    pair-mean-reversion state registered for [instrument] with the
    supplied bar."

    Wire-format DTO — primitives only, no domain values. [instrument]
    is the qualified [TICKER@MIC[/BOARD]] form parsed by the handler;
    OHLCV fields on [candle] are decimal strings (bit-exact roundtrip
    with [Decimal.to_string]).

    Naming: a {b bar} = ({i instrument}, {i timeframe}, {i candle}) —
    the contextualised market-data observation. The {b candle} field
    holds the pure OHLCV body without context.

    Triggered by:
      - the inbound [Bar_updated_integration_event] handler translating
        a broker-published bar (single production caller today);
      - future external entries (CLI replay, backtest harness) that
        want to drive pair-mr policies without going through the bus. *)

include module type of Apply_bar_command_t
include module type of Apply_bar_command_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
