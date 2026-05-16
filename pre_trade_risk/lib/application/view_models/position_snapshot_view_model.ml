include Position_snapshot_view_model_t
include Position_snapshot_view_model_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

type domain = Pre_trade_risk.Risk_view.Values.Position_snapshot.t

let of_domain (p : domain) : t =
  {
    instrument =
      Instrument_view_model.of_domain
        (Pre_trade_risk.Risk_view.Values.Position_snapshot.instrument p);
    quantity =
      Decimal.to_string (Pre_trade_risk.Risk_view.Values.Position_snapshot.quantity p);
    avg_price =
      Decimal.to_string (Pre_trade_risk.Risk_view.Values.Position_snapshot.avg_price p);
  }
