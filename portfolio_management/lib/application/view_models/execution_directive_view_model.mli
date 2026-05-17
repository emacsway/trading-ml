(** Read-model DTO for an execution directive. Tag + opaque
    per-strategy JSON params blob. The directive originates at
    portfolio_management (this view model) as part of a trader
    intent; pre_trade_risk and execution_management each mirror
    the wire shape on their own side per ADR-0001's
    BC-independence rule. *)

include module type of Execution_directive_view_model_t

include module type of Execution_directive_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
