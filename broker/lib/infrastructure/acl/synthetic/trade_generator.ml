(** Deterministic synthetic tape for backtest — the public-trade
    analogue of {!Generator} (candles). Turns one candle into a
    sequence of public-tape prints whose footprint reconstructs the
    candle's OHLC: the first print is the open, the last is the close,
    the high and low are touched, and sizes sum to ~volume. Aggressor
    side carries a mild directional bias (close > open -> more buys)
    plus noise, so cumulative delta mostly tracks price but occasionally
    diverges — enough to exercise the footprint signal path offline.

    NOTE: the delta here is *generated*, not observed. This tape
    validates footprint mechanics in backtest; it is not real
    microstructure and must not be read as alpha evidence — that needs a
    recorded live tape. *)

open Core

module Remote_public_trade_updated =
  Broker_domain.Remote_broker.Events.Remote_public_trade_updated

let generate ~(instrument : Instrument.t) ~(candle : Candle.t) ~tf_seconds ~n :
    Remote_public_trade_updated.t list =
  let open_ = Decimal.to_float candle.Candle.open_ in
  let high = Decimal.to_float candle.Candle.high in
  let low = Decimal.to_float candle.Candle.low in
  let close = Decimal.to_float candle.Candle.close in
  let volume = Decimal.to_float candle.Candle.volume in
  let ts0 = candle.Candle.ts in
  let n = max 4 n in
  let rng = Random.State.make [| 7; Int64.to_int ts0; n |] in
  (* Price path: open, high, low, interior fills, close — guarantees the
     extremes are touched and open/close are first/last. *)
  let interior =
    List.init (n - 4) (fun _ -> low +. Random.State.float rng (high -. low))
  in
  let prices = (open_ :: high :: low :: interior) @ [ close ] in
  let size = volume /. float_of_int n in
  let bias = if close > open_ then 0.6 else if close < open_ then 0.4 else 0.5 in
  let dt = float_of_int tf_seconds /. float_of_int n in
  List.mapi
    (fun i price ->
      let side =
        if Random.State.float rng 1.0 < bias then Some Side.Buy else Some Side.Sell
      in
      {
        Remote_public_trade_updated.instrument;
        side;
        quantity = Decimal.of_float size;
        price = Decimal.of_float price;
        ts = Int64.add ts0 (Int64.of_float (float_of_int i *. dt));
      })
    prices
