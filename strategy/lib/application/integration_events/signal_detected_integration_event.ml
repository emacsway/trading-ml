include Signal_detected_integration_event_t
include Signal_detected_integration_event_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

type domain = Signal.t

let direction_of_action : Signal.action -> string = function
  | Enter_long -> "UP"
  | Enter_short -> "DOWN"
  | Exit_long | Exit_short -> "FLAT"
  | Hold -> "FLAT"

let of_domain ~(strategy_id : string) ~(price : Decimal.t) (s : domain) : t =
  {
    strategy_id;
    instrument = Instrument_view_model.of_domain s.instrument;
    direction = direction_of_action s.action;
    strength = s.strength;
    price = Decimal.to_string price;
    reason = s.reason;
    occurred_at = Datetime.Iso8601.format s.ts;
  }
