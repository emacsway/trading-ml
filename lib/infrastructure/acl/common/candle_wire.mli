(** JSON parsing helpers for broker responses containing candles.

    Lives in ACL because it's entirely a wire-format concern —
    the domain {!Core.Candle.t} knows nothing about JSON. Tolerant
    decoders that handle common broker response variations. *)

open Core

val of_yojson_flex : Yojson.Safe.t -> Candle.t
(** Flexible per-bar decoder tolerant of common broker response
    variations. Each field name has several candidates:
    - timestamp: "timestamp", "time", "t", "ts"
    - OHLC:      plain or short ("open", "o"), decimal or wrapper
    - volume:    "volume", "vol", "v", "total_volume"

    Unknown fields are ignored; required ones fall through to 0
    rather than raise, so a partial response still yields a
    usable candle. *)
