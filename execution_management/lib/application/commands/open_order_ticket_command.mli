(** Open-OrderTicket command.

    Cross-BC: dispatched on the bus by order_management's saga
    after Account confirms the reservation (per ADR 0017 / ADR
    0020). EM subscribes and routes into the
    {!Open_order_ticket_command_workflow}.

    Generated wire shape from
    [shared/contracts/execution_management/commands/open_order_ticket_command.atd]
    via atdgen. The optional [execution_directive] carries the
    trader-intent strategy choice end-to-end (ADR 0019). Absent
    means the handler falls back to
    {!Execution_management.Order_ticket.Values.Execution_policy.default}. *)

include module type of Open_order_ticket_command_t

include module type of Open_order_ticket_command_j with type t := t

type directive = Execution_directive_view_model.t = {
  kind : string;
  params : string option;
}
(** Alias for the cross-referenced wire directive — the handler's
    pattern-match keeps the short name [directive] while the wire
    field is [execution_directive]. *)

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
