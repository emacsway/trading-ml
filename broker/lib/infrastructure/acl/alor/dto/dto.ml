(** Alor wire DTOs: decode JSON payloads into domain types, isolating
    wire-format concerns from the rest of the adapter.

    Collapse-rule [dto/dto.ml] does not pick up its siblings
    automatically — they are aliased here (same convention as
    {!Finam.Dto}). *)

open Core

module Wire = Wire
module Order = Order
module Trade = Trade

(** Per-bar decode. Alor's history/bar object is
    [{ time, open, high, low, close, volume }] (Simple) or the short
    [{ t, o, h, l, c, v }] (Slim); {!Acl_common.Candle_wire.of_yojson_flex}
    tolerates both. *)
let candle_of_json : Yojson.Safe.t -> Candle.t = Acl_common.Candle_wire.of_yojson_flex

(** Decode the [GET /md/v2/history] response — bars live under the
    [history] array. *)
let candles_of_json (j : Yojson.Safe.t) : Candle.t list =
  match Yojson.Safe.Util.member "history" j with
  | `List items -> List.map candle_of_json items
  | _ -> []
