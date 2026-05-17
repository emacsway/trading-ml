(** Read-model DTO for {!Order_ticket.Placement.t}. *)

include module type of Placement_view_model_t

include module type of Placement_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

val of_domain : Execution_management.Order_ticket.Placement.t -> t
