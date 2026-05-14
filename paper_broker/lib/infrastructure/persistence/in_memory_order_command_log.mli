(** In-memory adapter for the
    {!Paper_broker_store.Order_command_log.S} port.

    Coarse {!Stdlib.Mutex.t} around a {!Stdlib.Hashtbl.t}. One slot
    per aggregate captures the most recent [Submit] correlation_id
    and the most recent [Cancel] correlation_id; sufficient for
    current consumers (apply_bar workflow recovers the originating
    Submit's correlation_id). When a proper event log lands, this
    is replaced by an index over events. *)

include Paper_broker_store.Order_command_log.S

val create : unit -> t
