(** Integration event: paper_broker accepted a freshly-submitted order
    into its working book. Published on
    [in-memory://broker.order-accepted] after a successful
    [submit_order_command_workflow].

    The downstream EMS saga transitions
    [Awaiting_reservation → Submitted] on this. *)

include module type of Order_accepted_integration_event_t
include module type of Order_accepted_integration_event_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Paper_broker.Order.Events.Order_accepted.t

val of_domain : correlation_id:string -> domain -> t
