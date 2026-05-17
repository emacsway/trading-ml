(** Read-model DTO for an execution directive. Mirror of
    [portfolio_management/lib/application/view_models/execution_directive_view_model.ml].
    PTR carries this through unchanged — the gate is an approver,
    not an enricher. *)

include module type of Execution_directive_view_model_t

include module type of Execution_directive_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
