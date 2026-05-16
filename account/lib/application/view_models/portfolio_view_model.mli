(** Read-model DTO for {!Account.Portfolio.t}.

    Positions are projected as a flat list. The domain stores
    them keyed by instrument for O(log n) lookup, but the
    instrument identity is inside each entry, so the list form
    loses nothing across the wire.

    The wire shape is generated from
    [shared/contracts/account/view_models/portfolio_view_model.atd]
    via atdgen. *)

include module type of Portfolio_view_model_t

include module type of Portfolio_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Account.Portfolio.t

val of_domain : domain -> t
