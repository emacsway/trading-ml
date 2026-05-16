open Core
include Reservation_view_model_t
include Reservation_view_model_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

type domain = Account.Portfolio.Reservation.t

let of_domain (r : domain) : t =
  {
    id = r.id;
    side = Side.to_string r.side;
    instrument = Instrument_view_model.of_domain r.instrument;
    cover_qty = Decimal.to_string r.cover_qty;
    open_qty = Decimal.to_string r.open_qty;
    per_unit_collateral = Decimal.to_string r.per_unit_collateral;
  }
