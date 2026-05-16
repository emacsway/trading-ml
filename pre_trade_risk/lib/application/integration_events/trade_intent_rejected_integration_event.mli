(** Integration event: pre_trade_risk rejected a trade leg.

    Published by {!Assess_trade_intent_command_workflow} after
    {!Pre_trade_risk.Assessment.assess} returns [Reject reason].
    [correlation_id] echoes the originating command so the saga
    Process Manager terminates the corresponding instance through its
    compensation path (no Reserve_command is dispatched on a
    rejection).

    The wire shape is generated from
    [shared/contracts/pre_trade_risk/integration_events/trade_intent_rejected_integration_event.atd]
    via atdgen. *)

include module type of Trade_intent_rejected_integration_event_t

include module type of Trade_intent_rejected_integration_event_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
