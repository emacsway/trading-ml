include Portfolio_view_model_t
include Portfolio_view_model_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

type domain = Account.Portfolio.t

let of_domain (p : domain) : t =
  {
    cash = Decimal.to_string p.cash;
    realized_pnl = Decimal.to_string p.realized_pnl;
    positions = List.map (fun (_, pos) -> Position_view_model.of_domain pos) p.positions;
    reservations = List.map Reservation_view_model.of_domain p.reservations;
  }
