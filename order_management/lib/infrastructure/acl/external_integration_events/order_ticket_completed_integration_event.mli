(** Mirror of {!Execution_management_integration_events.Order_ticket_completed_integration_event.t}. *)

include module type of Order_ticket_completed_integration_event_t
include module type of Order_ticket_completed_integration_event_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
