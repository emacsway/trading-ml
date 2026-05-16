include Order_kind_view_model_t
include Order_kind_view_model_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

type domain = Order.kind

let of_domain (k : domain) : t =
  match k with
  | Market -> { type_ = "MARKET"; price = None; stop_price = None; limit_price = None }
  | Limit p ->
      {
        type_ = "LIMIT";
        price = Some (Decimal.to_string p);
        stop_price = None;
        limit_price = None;
      }
  | Stop p ->
      {
        type_ = "STOP";
        price = Some (Decimal.to_string p);
        stop_price = None;
        limit_price = None;
      }
  | Stop_limit { stop; limit } ->
      {
        type_ = "STOP_LIMIT";
        price = None;
        stop_price = Some (Decimal.to_string stop);
        limit_price = Some (Decimal.to_string limit);
      }
