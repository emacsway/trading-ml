let parse (data : Yojson.Safe.t) : Core.Candle.t =
  Acl_common.Candle_wire.of_yojson_flex data
