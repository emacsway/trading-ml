(** Read-model DTO for {!Core.Candle.t}.

    OHLCV as primitives: [ts] is an ISO-8601 datetime string
    ([YYYY-MM-DDTHH:MM:SSZ]) for cross-language wire-format
    consistency with the rest of the BC's commands and integration
    events; prices/volume are decimal strings accepted by
    {!Decimal.of_string} — bit-exact round-trip with the domain.

    The wire shape is generated from
    [shared/contracts/broker/view_models/candle_view_model.atd]
    via atdgen. *)

include module type of Candle_view_model_t

include module type of Candle_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Core.Candle.t

val of_domain : domain -> t
