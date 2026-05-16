(** Integration event: a working order in paper_broker's book was
    cancelled. Published on [in-memory://broker.order-cancelled]
    after a successful [cancel_pending_order_command_workflow]. *)

include module type of Order_cancelled_integration_event_t
include module type of Order_cancelled_integration_event_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Paper_broker.Order.Events.Order_cancelled.t

val of_domain : correlation_id:string -> domain -> t
