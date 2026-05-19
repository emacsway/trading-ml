(** Dimensionless conviction of an alpha source about its
    {!Direction.t} forecast, on the closed interval [\[0, 1\]].
    Constructed at the application-layer boundary from external
    wire data and consumed thereafter as the load-bearing input
    to single-asset sizing — strictly internal to the domain.

    [0] denotes "no conviction" (collapses scalar intents to a
    flat target downstream); [1] denotes maximal conviction
    (allocates the source's full per-book budget). Values
    outside [\[0, 1\]] are rejected at construction; downstream
    code is therefore allowed to assume the invariant holds. *)

type t

val zero : t
(** Identity element: the canonical "no conviction" value. *)

val one : t
(** Top of the range: full conviction. *)

val of_decimal : Decimal.t -> t
(** [of_decimal d] wraps [d] as a [Strength.t].
    Raises [Invalid_argument] when [d] is outside [\[0, 1\]]. *)

val to_decimal : t -> Decimal.t
(** Project to the underlying scalar for arithmetic. *)

val of_float : float -> t
(** Convenience boundary constructor for wire DTOs that carry
    [strength] as a JSON number. Equivalent to
    [of_decimal (Decimal.of_float f)] with the same range check. *)

val equal : t -> t -> bool

val compare : t -> t -> int
