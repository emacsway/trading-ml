(** Integration event: an OrderTicket reached terminal Filled
    (Σ filled = total). *)

include module type of Order_ticket_completed_integration_event_t

include module type of Order_ticket_completed_integration_event_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

val of_domain :
  correlation_id:string ->
  Execution_management.Order_ticket.Events.Ticket_completed.t ->
  t
