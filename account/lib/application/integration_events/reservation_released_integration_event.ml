include Reservation_released_integration_event_t
include Reservation_released_integration_event_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

type domain = Account.Portfolio.Events.Reservation_released.t

let of_domain (ev : domain) : t =
  {
    reservation_id = ev.reservation_id;
    side = Core.Side.to_string ev.side;
    instrument = Instrument_view_model.of_domain ev.instrument;
  }
