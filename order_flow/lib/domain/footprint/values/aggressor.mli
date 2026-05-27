(** Aggressor side of a tape print — which side crossed the spread to
    cause the execution.

    Deliberately distinct from {!Core.Side}. [Side] is the direction of
    an {e order} and has two inhabitants. An aggressor classifies an
    {e executed print} and admits a third case, [Indeterminate], for
    prints with no initiator: opening/closing auction crosses and
    negotiated (off-book) trades, which an order-driven venue reports
    without a buy/sell aggressor (e.g. Finam's [SIDE_UNSPECIFIED]).
    Reusing [Side] here would erase that case and force a false
    buy/sell choice on volume that has no directional meaning. *)

type t = Buy | Sell | Indeterminate

val to_string : t -> string

val of_string : string -> t
(** Accepts [BUY|SELL] (case-insensitive) and the venues' "no
    aggressor" tokens ([UNSPECIFIED|NONE|""]) as [Indeterminate];
    raises [Invalid_argument] on any other input. *)
(*@ r = of_string s
    raises Invalid_argument _ -> true *)

val sign : t -> int
(** Directional contribution to delta: [Buy] = [+1] (lifted the ask),
    [Sell] = [-1] (hit the bid), [Indeterminate] = [0] (no directional
    information — auction/negotiated print). Unlike [Side.sign] this is
    not guaranteed non-zero. *)
(*@ r = sign t
    ensures match t with
            | Buy -> r = 1
            | Sell -> r = -1
            | Indeterminate -> r = 0 *)
