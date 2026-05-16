include Order_cancelled_integration_event_t
include Order_cancelled_integration_event_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

type domain = Paper_broker.Order.Events.Order_cancelled.t

let of_domain ~(correlation_id : string) (ev : domain) : t =
  {
    correlation_id;
    placement_id = Paper_broker.Order.Values.Placement_id.to_int ev.placement_id;
    id = ev.id;
    instrument = Instrument_view_model.of_domain ev.instrument;
    cancelled_ts = Datetime.Iso8601.format ev.cancelled_ts;
  }
