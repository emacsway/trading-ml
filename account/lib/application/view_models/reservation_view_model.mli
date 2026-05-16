(** Read-model DTO for {!Account.Portfolio.Reservation.t}.

    The wire shape is generated from
    [shared/contracts/account/view_models/reservation_view_model.atd]
    via atdgen. *)

include module type of Reservation_view_model_t

include module type of Reservation_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Account.Portfolio.Reservation.t

val of_domain : domain -> t
