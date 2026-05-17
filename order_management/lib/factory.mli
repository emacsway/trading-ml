(** Order_management BC composition root.

    Hosts the {!Order_process_manager} saga: subscribes to
    pre_trade_risk's [Trade_intent_approved] (saga start) and to
    Account's [Amount_reserved] / [Reservation_rejected] (saga
    completion path). Dispatches Reserve_command to Account at
    start and Open_order_ticket_command (cross-BC wire) to
    execution_management on terminal [Done].

    Step-2 scope: saga only. Intake gate (kill_switch / rate_limit)
    lives in execution_management today and re-homes in
    pre_trade_risk in step 2.5 (per ADR 0020 + follow-up). *)

type t = { http_handler : Inbound_http.Route.handler }

val build : bus:Bus.bus -> t
