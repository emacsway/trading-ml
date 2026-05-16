(** Read-model DTO for {!Common.Signal.t}. *)

include module type of Signal_view_model_t
include module type of Signal_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Common.Signal.t

val of_domain : domain -> t
