(** Mirror of [pre_trade_risk/lib/application/view_models/execution_directive_view_model.ml].
    Wire shape regenerated from PTR's .atd contract; consumed by
    EM's external_integration_events lib through the cross-ref in
    [trade_intent_approved_integration_event.atd]. *)

include module type of Execution_directive_view_model_t
include module type of Execution_directive_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
