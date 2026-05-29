open Core

type t = Time of Timeframe.t | Volume of Decimal.t

let admits_time_close = function
  | Time _ -> true
  | Volume _ -> false

let period_seconds = function
  | Time tf -> Timeframe.to_seconds tf
  | Volume _ -> invalid_arg "Bar_boundary.period_seconds: Volume boundary has no period"

let bucket_start b ~ts =
  match b with
  | Time tf ->
      let period = Int64.of_int (Timeframe.to_seconds tf) in
      Int64.sub ts (Int64.rem ts period)
  | Volume _ ->
      invalid_arg "Bar_boundary.bucket_start: Volume boundary has no time bucket"
