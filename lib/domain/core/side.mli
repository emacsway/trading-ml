(** Trade direction. *)

type t = Buy | Sell

val to_string : t -> string
val of_string : string -> t
val opposite : t -> t
val sign : t -> int
