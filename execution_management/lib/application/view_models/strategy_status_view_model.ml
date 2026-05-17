module Strategy = Execution_management.Order_ticket.Strategies.Strategy

include Strategy_status_view_model_t
include Strategy_status_view_model_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

let kind_of_strategy (s : Strategy.t) : string =
  match s with
  | Immediate _ -> "IMMEDIATE"
  | Twap _ -> "TWAP"
  | Vwap _ -> "VWAP"
  | Pov _ -> "POV"
  | Iceberg _ -> "ICEBERG"
  | Implementation_shortfall _ -> "IMPLEMENTATION_SHORTFALL"

let of_domain (s : Strategy.t) : t =
  { kind = kind_of_strategy s; is_complete = Strategy.is_complete s }
