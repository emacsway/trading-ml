(** Command: operator-initiated cancel of an in-flight ticket.

    Wire shape generated from
    [shared/contracts/execution_management/commands/cancel_order_ticket_command.atd].
    The [reason] field is a controlled vocabulary mirroring
    {!Values.Cancel_reason.t}: ["operator" | "kill_switch" |
    "risk_limit_breach"]. Unknown values are rejected by the
    handler. *)

include module type of Cancel_order_ticket_command_t

include module type of Cancel_order_ticket_command_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
