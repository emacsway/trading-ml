(** Wire-format command: cancel a working order by its
    paper_broker-assigned [id]. The [correlation_id] is the
    saga-instance identifier of the cancellation request itself —
    distinct from the originating submit's [correlation_id], which
    {!Cancel_pending_order_command_workflow.execute} retrieves
    from the persisted {!Pending_order.t} so the outbound
    integration event echoes the submit-time saga.

    The wire shape is generated from
    [shared/contracts/paper_broker/commands/cancel_pending_order_command.atd]
    via atdgen. *)

include module type of Cancel_pending_order_command_t

include module type of Cancel_pending_order_command_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
