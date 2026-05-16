open Core

include Amount_reserved_integration_event_t
include Amount_reserved_integration_event_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

type domain = Account.Portfolio.Events.Amount_reserved.t

let of_domain ~(correlation_id : string) (ev : domain) : t =
  {
    correlation_id;
    reservation_id = ev.reservation_id;
    side = Side.to_string ev.side;
    instrument = Instrument_view_model.of_domain ev.instrument;
    quantity = Decimal.to_string ev.quantity;
    price = Decimal.to_string ev.price;
    reserved_cash = Decimal.to_string ev.reserved_cash;
  }
