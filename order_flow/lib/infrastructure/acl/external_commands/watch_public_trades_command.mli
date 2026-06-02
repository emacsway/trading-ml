(** order_flow-side outbound DTO mirror of {b broker.watch-public-trades-command}.

    Structural-only: a single qualified [symbol] string. Wire shape
    regenerated from the producer's (broker BC) .atd contract — the
    order_flow BC mirrors it independently (ADR 0001), no code-level
    dependency on the broker BC. *)

include module type of Watch_public_trades_command_t
include module type of Watch_public_trades_command_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
