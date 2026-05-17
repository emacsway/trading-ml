(** Read-model DTO for {!Order_ticket.Values.Execution_directive.t}.
    Carries the strategy tag plus an opaque per-strategy params
    JSON-object string. *)

include module type of Execution_directive_view_model_t

include module type of Execution_directive_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

val of_domain : Execution_management.Order_ticket.Values.Execution_directive.t -> t
