type t = {
  instrument : Core.Instrument.t;
  ts : int64;
  high : Decimal.t;
  low : Decimal.t;
  close : Decimal.t;
  volume : Decimal.t;
  delta : Decimal.t;
  poc_price : Decimal.t;
}
