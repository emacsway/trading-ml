(** Read-model DTO for {!Account.Portfolio.Values.Position.t}.

    The wire shape is generated from
    [shared/contracts/account/view_models/position_view_model.atd]
    via atdgen. *)

include module type of Position_view_model_t

include module type of Position_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Account.Portfolio.Values.Position.t

val of_domain : domain -> t
