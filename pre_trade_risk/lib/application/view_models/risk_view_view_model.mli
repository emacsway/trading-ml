(** Read-side projection of the full {!Pre_trade_risk.Risk_view.t}
    aggregate — diagnostic snapshot for HTTP / SSE consumers.

    The wire shape is generated from
    [shared/contracts/pre_trade_risk/view_models/risk_view_view_model.atd]
    via atdgen. *)

include module type of Risk_view_view_model_t

include module type of Risk_view_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Pre_trade_risk.Risk_view.t

val of_domain : domain -> t
