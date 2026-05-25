(** Inbound WS bar frame. Alor's [BarsGetAndSubscribe] data payload is
    a bare OHLCV object [{ time, open, high, low, close, volume }] with
    no instrument / timeframe of its own — the [(instrument, timeframe)]
    context is recovered from the frame's [guid] by {!Ws_bridge}, so
    this module decodes only the candle itself. *)

val parse : Yojson.Safe.t -> Core.Candle.t
(** Decode a bar frame's [data] object into a candle. Tolerant of the
    Simple ([time/open/…]) and Slim ([t/o/…]) field names. *)
