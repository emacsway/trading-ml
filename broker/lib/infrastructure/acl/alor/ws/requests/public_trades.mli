(** WS request encoder for the Alor public tape
    ([AllTradesGetAndSubscribe]) — all trades on one instrument, distinct
    from the personal-portfolio [TradesGetAndSubscribeV2]. Mirrors
    {!Bars} minus the timeframe; [depth:0] = live-only (no backfill). *)

open Core

val subscribe :
  cfg:Config.t ->
  token:string ->
  guid:string ->
  instrument:Instrument.t ->
  unit ->
  Yojson.Safe.t
