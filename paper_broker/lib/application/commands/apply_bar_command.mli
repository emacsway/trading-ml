(** Wire-format command: a new OHLCV bar has been observed for an
    instrument. Wire-byte-equivalent to the
    [portfolio_management.Apply_bar_command] so the same
    [broker.bar-updated] channel can be consumed by either BC. *)

include module type of Apply_bar_command_t
include module type of Apply_bar_command_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
