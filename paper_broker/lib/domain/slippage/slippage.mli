module Values : module type of Values

(** Pure slippage application: shift the fill price away from the
    trader by a [Slippage_bps]-bounded amount.

    For [Buy]:  [result = price * (1 + bps / 10_000)] — buys pay up.
    For [Sell]: [result = price * (1 - bps / 10_000)] — sells receive less.

    When [bps = 0] the operation is the identity, regardless of side
    or price. *)

val apply : bps:Values.Slippage_bps.t -> Core.Side.t -> Decimal.t -> Decimal.t
(*@ r = apply ~bps side price
    ensures bps = Values.Slippage_bps.zero -> r = price *)
