(** Inbound command to the Broker BC: the release counterpart of
    {!Watch_public_trades_command.t}. "I no longer need the public trade
    tape for this instrument."

    Wire-format DTO — a single qualified [symbol] string. Fire-and-forget;
    the adapter-side refcount closes the upstream tape only on the 1->0
    transition, leaving the operator watchlist's own subscription (if any)
    untouched. An unwatch with no matching prior watch is a benign no-op. *)

include module type of Unwatch_public_trades_command_t
include module type of Unwatch_public_trades_command_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
