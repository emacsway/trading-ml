(** Slippage configuration expressed in basis points: the spread cost
    the simulator charges on aggressive (price-seeking) orders.

    Applied to [Market] and [Stop] orders by [Slippage.apply], which
    moves the fill price away from the trader by [price * bps / 10_000].
    [Limit] and [Stop_limit] orders are not slippable — the trader
    chose a price ceiling/floor and the simulator honours it.

    Invariant: [bps >= 0]. Zero is the canonical "no slippage"
    setting used by deterministic tests and the synthetic-data
    backtest. *)

type t = private Decimal.t

val of_decimal : Decimal.t -> t
(** Raises [Invalid_argument] when [d < 0]. *)

val to_decimal : t -> Decimal.t

val zero : t
(** [0] basis points; convenient default for tests / synthetic
    deployments. *)

val equal : t -> t -> bool
val compare : t -> t -> int
