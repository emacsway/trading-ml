(** Inbound command to the Broker BC: "I want the public trade tape for
    this instrument flowing on the bus while I hold this subscription
    open."

    Wire-format DTO — a single qualified [symbol] string, no
    {!Core.Instrument.t}. The atd source is the single source of truth for
    the wire shape; atdgen emits the typed record (_t) and JSON codec (_j).

    The tape analogue of {!Watch_bars_command}: it carries no timeframe
    because the public tape is per-instrument, not per-period. Used by the
    order_flow BC to pull a non-watchlist instrument's tape on demand when
    a footprint subscription first needs it. Fire-and-forget; no
    correlation id, no response IE. The matching
    {!Unwatch_public_trades_command} releases this caller's interest;
    other callers' watches on the same instrument are unaffected (refcount
    on the adapter side). *)

include module type of Watch_public_trades_command_t
include module type of Watch_public_trades_command_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
