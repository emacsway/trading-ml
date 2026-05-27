(** A single executed trade on the public tape — a "print" — the atomic
    input of order-flow analysis.

    [ts] is the venue's execution time in unix epoch seconds (UTC),
    matching {!Core.Candle} and {!Clock}. Sub-second resolution is
    deliberately not modelled: intra-bar print order is provably
    irrelevant to the resulting footprint (see the fold-order
    independence lemma in [footprint.mlw]), so seconds suffice for bar
    assignment and nothing downstream depends on finer ordering. *)

(*@ function dec_raw (d : Decimal.t) : integer *)
(** Local alias for the scaled-integer projection of [Decimal.t]; see
    [core/candle.mli] for why this stub is repeated per file under
    Gospel 0.3.x. *)

type t = private {
  price : Decimal.t;
  size : Decimal.t;  (** strictly positive traded quantity *)
  ts : int64;  (** execution time, unix epoch seconds (UTC) *)
  aggressor : Aggressor.t;
}

val make : price:Decimal.t -> size:Decimal.t -> ts:int64 -> aggressor:Aggressor.t -> t
(** Raises [Invalid_argument] when [size <= 0]. Price is left
    unconstrained: calendar spreads and some derivatives legitimately
    print at zero or negative prices. *)
(*@ p = make ~price ~size ~ts ~aggressor
    raises Invalid_argument _ -> not (dec_raw size > 0) *)
