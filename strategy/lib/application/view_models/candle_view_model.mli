(** Read-model DTO for {!Core.Candle.t}.

    OHLCV as primitives: [ts] is a unix epoch-seconds int64,
    prices/volume are decimal strings accepted by
    {!Decimal.of_string} — bit-exact round-trip with the
    domain. The UI parses them with its own decimal library;
    [Number(x)] would lose precision the same way OCaml's
    {!Decimal.of_float} does. *)

include module type of Candle_view_model_t
include module type of Candle_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Core.Candle.t

val of_domain : domain -> t
