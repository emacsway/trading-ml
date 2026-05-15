type t = {
  id : string;
  placement_id : Values.Placement_id.t;
  instrument : Core.Instrument.t;
  cancelled_ts : int64;
}
