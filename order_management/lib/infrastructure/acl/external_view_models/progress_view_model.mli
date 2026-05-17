(** Mirror of {!Execution_management_view_models.Progress_view_model.t}. *)

include module type of Progress_view_model_t
include module type of Progress_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
