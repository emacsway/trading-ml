(** Domain Event: a footprint bar sealed — the complete order-flow
    shape for [(instrument, boundary)] over the bucket opened at
    [open_ts]. Emitted by [Footprint.seal].

    Carries objective facts only: OHLCV reconstructed from the bar's own
    prints, the signed [delta], the volume Point of Control [poc_price],
    and the per-price [clusters]. Thresholded interpretations (stacked
    imbalance, CVD divergence) are deliberately absent — those belong to
    the strategy BC, which consumes this event. *)

type t = {
  instrument : Core.Instrument.t;
  boundary : Values.Bar_boundary.t;
  open_ts : int64;
  open_price : Decimal.t;
  high : Decimal.t;
  low : Decimal.t;
  close : Decimal.t;
  volume : Decimal.t;  (** total traded volume = sum of cluster totals *)
  delta : Decimal.t;  (** bar delta = sum of cluster deltas (buy - sell) *)
  poc_price : Decimal.t;  (** Point of Control: price of the max-volume cluster *)
  clusters : Values.Cluster.t list;  (** ascending by price *)
}
