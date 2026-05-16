(** Integration event: the kill switch tripped — submissions are
    halted until an operator resets it. Telemetry-only consumers
    (SSE, audit, alerting).

    The wire shape is generated from
    [shared/contracts/execution_management/integration_events/kill_switch_tripped_integration_event.atd]
    via atdgen. *)

include module type of Kill_switch_tripped_integration_event_t

include module type of Kill_switch_tripped_integration_event_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
