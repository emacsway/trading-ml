type t = {
  id : string;
  placement_id : Values.Placement_id.t;
  instrument : Core.Instrument.t;
  side : Core.Side.t;
  quantity : Decimal.t;
  created_ts : int64;
}
