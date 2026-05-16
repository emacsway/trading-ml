open Core

include Candle_view_model_t
include Candle_view_model_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

type domain = Candle.t

let of_domain (c : domain) : t =
  {
    ts = Datetime.Iso8601.format c.ts;
    open_ = Decimal.to_string c.open_;
    high = Decimal.to_string c.high;
    low = Decimal.to_string c.low;
    close = Decimal.to_string c.close;
    volume = Decimal.to_string c.volume;
  }
