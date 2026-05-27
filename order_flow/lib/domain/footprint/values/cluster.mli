(** One price level of a footprint bar: volume traded at a single price,
    split by the aggressor that caused each print.

    - [buy_volume]  — [Buy]-aggressor volume (prints that lifted the ask)
    - [sell_volume] — [Sell]-aggressor volume (prints that hit the bid)
    - [indeterminate_volume] — auction/negotiated prints with no
      aggressor; counted in {!total} but excluded from {!delta}, so
      directionless volume never fabricates a delta signal.

    All three buckets are non-negative. The record carries no smart
    constructor: {!empty} starts every bucket at zero and {!add} only
    ever adds a (positive) print size, so the invariant holds by
    construction — proved in [cluster.mlw]. *)

(*@ function dec_raw (d : Decimal.t) : integer *)

type t = private {
  price : Decimal.t;
  buy_volume : Decimal.t;
  sell_volume : Decimal.t;
  indeterminate_volume : Decimal.t;
}

val empty : price:Decimal.t -> t
(*@ c = empty ~price
    ensures dec_raw c.buy_volume = 0
    ensures dec_raw c.sell_volume = 0
    ensures dec_raw c.indeterminate_volume = 0 *)

val add : t -> aggressor:Aggressor.t -> size:Decimal.t -> t
(** Routes [size] into the bucket selected by [aggressor]. [size] is
    expected positive (guaranteed upstream by {!Print.make}); a
    non-positive size would break the non-negativity invariant. Total
    volume grows by exactly [size] regardless of aggressor. *)
(*@ c' = add c ~aggressor ~size
    ensures dec_raw c'.buy_volume + dec_raw c'.sell_volume
            + dec_raw c'.indeterminate_volume
          = dec_raw c.buy_volume + dec_raw c.sell_volume
            + dec_raw c.indeterminate_volume + dec_raw size *)

val total : t -> Decimal.t
(** [buy_volume + sell_volume + indeterminate_volume]. *)

val delta : t -> Decimal.t
(** [buy_volume - sell_volume]. Indeterminate volume is excluded. *)
(*@ d = delta c
    ensures dec_raw d = dec_raw c.buy_volume - dec_raw c.sell_volume *)
