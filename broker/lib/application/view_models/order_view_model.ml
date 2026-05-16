open Core
include Order_view_model_t
include Order_view_model_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

let of_domain ~(placement_id : int) (o : Order.t) : t =
  {
    placement_id;
    instrument = Instrument_view_model.of_domain o.instrument;
    side = Side.to_string o.side;
    quantity = Decimal.to_string o.quantity;
    filled = Decimal.to_string o.filled;
    remaining = Decimal.to_string o.remaining;
    kind = Order_kind_view_model.of_domain o.kind;
    tif = Order.tif_to_string o.tif;
    status = Order.status_to_string o.status;
    created_ts = o.created_ts;
  }
