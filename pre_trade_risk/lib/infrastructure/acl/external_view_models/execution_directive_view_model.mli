(** Mirror of [portfolio_management/lib/application/view_models/execution_directive_view_model.ml].
    Wire shape regenerated from PM's .atd contract; the ACL
    translator in
    [trade_intents_planned_integration_event_handler.ml]
    converts it into PTR's internal [Execution_directive_view_model.t]. *)

include module type of Execution_directive_view_model_t
include module type of Execution_directive_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
