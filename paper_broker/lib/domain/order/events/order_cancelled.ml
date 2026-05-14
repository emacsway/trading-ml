type t = {
  id : string;
  reservation_id : Values.Reservation_id.t;
  instrument : Core.Instrument.t;
  cancelled_ts : int64;
}
