(** Integration event: broker accepted a submission.
    Published by {!Submit_order_command_workflow} after a
    successful {!Broker.place_order} call whose returned status is
    not [Rejected].

    [placement_id] echoes the saga key supplied in
    {!Submit_order_command.t}; it is the only identity of an
    in-flight order in our model. Consumers (Account compensation,
    audit, SSE) match by [correlation_id] + [placement_id]. *)

include module type of Order_accepted_integration_event_t
include module type of Order_accepted_integration_event_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
