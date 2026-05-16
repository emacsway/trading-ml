(** Outbound view-model mirror of {!Core.Instrument.t}. Used by the
    BC's outbound view-models.

    The wire shape is generated from
    [shared/contracts/pre_trade_risk/view_models/instrument_view_model.atd]
    via atdgen. *)

include module type of Instrument_view_model_t

include module type of Instrument_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Core.Instrument.t

val of_domain : domain -> t
