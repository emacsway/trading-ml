(** Mirror of {!Pre_trade_risk_view_models.Execution_directive_view_model.t}. *)

include module type of Execution_directive_view_model_t
include module type of Execution_directive_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
