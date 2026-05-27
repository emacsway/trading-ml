(** Footprint strategy: CVD / price divergence (implements
    {!Footprint_strategy.S}).

    Maintains the true cumulative volume delta — the running sum of each
    sealed bar's signed [delta], the real figure rather than the
    candle-range proxy {!Cvd} must use — and over a [lookback] window
    flags divergence between price and flow:

    - price prints a new window high while CVD does not -> bearish
      divergence (buying not confirming the high): exit long / enter short;
    - price prints a new window low while CVD does not -> bullish
      divergence (selling not confirming the low): exit short / enter long.

    [lookback] is the one tunable (regime-dependent); per ADR 0032 such
    thresholds live in the strategy BC, not in order_flow. *)

type state
type params = { lookback : int }

val name : string
val default_params : params
val init : params -> state
val on_footprint : state -> Core.Instrument.t -> Footprint_bar.t -> state * Signal.t
