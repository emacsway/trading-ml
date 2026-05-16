open Core

include Reservation_filled_integration_event_t
include Reservation_filled_integration_event_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

type domain = Account.Portfolio.Events.Reservation_filled.t

let of_domain ~(correlation_id : string) (ev : domain) : t =
  {
    correlation_id;
    reservation_id = ev.reservation_id;
    instrument = Instrument_view_model.of_domain ev.instrument;
    side = Side.to_string ev.side;
    filled_quantity = Decimal.to_string ev.filled_quantity;
    fill_price = Decimal.to_string ev.fill_price;
    fee = Decimal.to_string ev.fee;
    new_position_quantity = Decimal.to_string ev.new_position_quantity;
    new_avg_price = Decimal.to_string ev.new_avg_price;
    new_cash = Decimal.to_string ev.new_cash;
  }
