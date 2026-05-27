open Core

type t = Time of Timeframe.t

let admits_time_close = function
  | Time _ -> true

let period_seconds = function
  | Time tf -> Timeframe.to_seconds tf

let bucket_start (Time tf) ~ts =
  let period = Int64.of_int (Timeframe.to_seconds tf) in
  Int64.sub ts (Int64.rem ts period)
