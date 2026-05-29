open Core
include Footprint_completed_integration_event_t
include Footprint_completed_integration_event_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

type domain = Footprint.Events.Footprint_completed.t

let of_domain (ev : domain) : t =
  (* Serialised boundary token carried in the wire [timeframe] field. A
     Time bar is fully described by its timeframe token (M1 … MN1); a
     Volume bar has no timeframe, so it is tagged [VOL:<cap>]. This reuses
     the existing string field as a stopgap — the proper fix, foreseen in
     the .atd, is a structured boundary discriminator on the wire, a
     contract change deferred with the rest of the Volume-bar follow-up
     (exact-cap split, Tick). *)
  let timeframe =
    match ev.Footprint.Events.Footprint_completed.boundary with
    | Footprint.Values.Bar_boundary.Time tf -> Timeframe.to_string tf
    | Footprint.Values.Bar_boundary.Volume cap -> "VOL:" ^ Decimal.to_string cap
  in
  {
    instrument = Instrument_view_model.of_domain ev.instrument;
    timeframe;
    open_ts = Datetime.Iso8601.format ev.open_ts;
    open_price = Decimal.to_string ev.open_price;
    high = Decimal.to_string ev.high;
    low = Decimal.to_string ev.low;
    close = Decimal.to_string ev.close;
    volume = Decimal.to_string ev.volume;
    delta = Decimal.to_string ev.delta;
    poc_price = Decimal.to_string ev.poc_price;
    clusters = List.map Cluster_view_model.of_domain ev.clusters;
  }
