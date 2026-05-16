include Signal_view_model_t
include Signal_view_model_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

type domain = Signal.t

let of_domain (s : domain) : t =
  {
    ts = s.ts;
    instrument = Instrument_view_model.of_domain s.instrument;
    action = Signal.action_to_string s.action;
    strength = s.strength;
    stop_loss = Option.map Decimal.to_string s.stop_loss;
    take_profit = Option.map Decimal.to_string s.take_profit;
    reason = s.reason;
  }
