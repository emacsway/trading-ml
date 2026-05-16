(** Read-side projection of {!Pre_trade_risk.Risk_view.Values.Position_snapshot.t}.
    Decimal fields serialised as strings for bit-exact round-trip
    (project rule, see ADR 0007).

    The wire shape is generated from
    [shared/contracts/pre_trade_risk/view_models/position_snapshot_view_model.atd]
    via atdgen. *)

include module type of Position_snapshot_view_model_t

include module type of Position_snapshot_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Pre_trade_risk.Risk_view.Values.Position_snapshot.t

val of_domain : domain -> t
