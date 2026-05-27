type t = {
  instrument : Core.Instrument.t;
  boundary : Values.Bar_boundary.t;
  open_ts : int64;
  open_price : Decimal.t;
  high : Decimal.t;
  low : Decimal.t;
  close : Decimal.t;
  volume : Decimal.t;
  delta : Decimal.t;
  poc_price : Decimal.t;
  clusters : Values.Cluster.t list;
}
