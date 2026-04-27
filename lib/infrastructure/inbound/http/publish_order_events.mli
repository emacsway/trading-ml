(** Publisher of {!Workflows.Place_order_workflow} events to the SSE
    [order] channel. *)

val json_of_event : Workflows.Place_order_workflow.event -> Yojson.Safe.t
(** Project a single workflow event to its outbound JSON envelope. *)

val publish : Stream.t -> Workflows.Place_order_workflow.event list -> unit
(** Publish every event in [events] to the [order] channel of [registry]
    in the order given. *)
