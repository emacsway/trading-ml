(** Execution_management BC composition root.

    Hosts the OrderTicket aggregate, the six execution strategies,
    and the broker dialog. Subscribes to its own inbound
    [Open_order_ticket_command] (cross-BC from order_management,
    per ADR 0020) plus the five broker IE topics; publishes
    Submit / Cancel commands to the broker and Order_ticket_*
    telemetry IEs.

    Intake-gating (kill_switch / rate_limit) and reservation-cycle
    orchestration live elsewhere (pre_trade_risk + order_management
    respectively). *)

type t = { http_handler : Inbound_http.Route.handler }

val build : bus:Bus.bus -> now:(unit -> int64) -> t
(** [now] supplies ambient time (epoch seconds) used by aggregate
    operations on inbound broker IEs. See ADR 0013. *)
