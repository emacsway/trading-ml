type t = {
  id : string;
  reservation_id : Values.Reservation_id.t;
  instrument : Core.Instrument.t;
  side : Core.Side.t;
  quantity : Decimal.t;
  created_ts : int64;
}
