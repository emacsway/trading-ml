(** A sealed footprint bar as the strategy BC sees it — its own view,
    reconstructed by the inbound ACL from order_flow's footprint_completed
    integration event (no order_flow domain import; BC isolation).

    Carries OHLC + volume + the signed [delta] (the real aggressor-flow
    figure the candle-range {!Cvd} proxy only estimates) and the volume
    Point of Control. Per-price clusters exist in the upstream event but
    are not mirrored here until a cluster-based signal needs them. *)

type t = {
  instrument : Core.Instrument.t;
  ts : int64;  (** bar open time, unix epoch seconds (UTC) *)
  high : Decimal.t;
  low : Decimal.t;
  close : Decimal.t;
  volume : Decimal.t;
  delta : Decimal.t;  (** signed: buy-aggressor minus sell-aggressor volume *)
  poc_price : Decimal.t;
}
