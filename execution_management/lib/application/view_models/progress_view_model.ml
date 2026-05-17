module Progress = Execution_management.Order_ticket.Values.Progress

include Progress_view_model_t
include Progress_view_model_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

let of_domain (p : Progress.t) : t =
  {
    total_quantity = Decimal.to_string p.total_quantity;
    cumulative_filled = Decimal.to_string p.cumulative_filled;
    remaining_quantity = Decimal.to_string (Progress.remaining_quantity p);
    total_fees = Decimal.to_string p.total_fees;
  }
