(** In-process volatile {!Broker_store.Order_command_log.S}.

    Single hashtable keyed by [placement_id], with a [Mutex] for
    the read-modify-write paths. Sufficient for live mode under
    Eio's single-domain scheduler and for the in-process
    integration tests; a persistent backend will replace it once
    broker grows a real event log. *)

include Broker_store.Order_command_log.S

val create : unit -> t
