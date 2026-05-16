include Risk_view_view_model_t
include Risk_view_view_model_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

type domain = Pre_trade_risk.Risk_view.t

let of_domain (v : domain) : t =
  {
    book_id = Pre_trade_risk.Common.Book_id.to_string (Pre_trade_risk.Risk_view.book_id v);
    cash = Decimal.to_string (Pre_trade_risk.Risk_view.cash v);
    positions =
      List.map Position_snapshot_view_model.of_domain
        (Pre_trade_risk.Risk_view.positions v);
  }
