(** [export-training-data] — offline dataset builder for the GBT
    pipeline.

    Pulls historical bars from a broker, streams them through the
    same feature roster {!Strategies.Gbt_strategy} uses at inference
    (RSI / MFI / Bollinger %B), computes a three-class label from
    forward returns, and writes [features...,label] rows as CSV.
    The output is consumed by the Python training script
    ([docs/architecture/ml/gbt.md] has the full pipeline).

    Column alignment with the strategy is load-bearing: any drift
    between what this tool writes and what [Gbt_strategy] computes
    at inference silently garbages predictions. The fix is to keep
    the feature assembly in lockstep — if you change one, change
    both. *)

open Core
open Broker_boot

let usage () =
  prerr_endline {|export-training-data
  --broker finam|bcs --symbol SBER@MISX --output PATH
  [--timeframe M1|M5|M15|M30|H1|H4|D1] (default H1)
  [--from YYYY-MM-DD]    (default: --to minus 365 days)
  [--to   YYYY-MM-DD]    (default: now)
  [--horizon N]          (default 5 — bars ahead for label)
  [--threshold F]        (default 0.005 — ±band for 3-class label)
  [--secret S] [--account A] [--client-id C]  (or matching env vars)|};
  exit 2

(** [YYYY-MM-DD] or full ISO-8601; dates without a [T] suffix pick
    midnight UTC so the range boundaries are unambiguous. *)
let parse_date s =
  let s = if String.contains s 'T' then s else s ^ "T00:00:00Z" in
  Candle_json.parse_iso8601 s

(** Paginate bars across a date range. Brokers cap per-call bar
    count (BCS hard-limits at 1440, Finam has a similar but less
    documented ceiling); we walk [to_ts] backwards in chunks until
    [from_ts] is covered or the broker stops making progress. The
    returned list is chronological with duplicates on chunk
    boundaries removed. *)
let paginate_bars ~fetch ~from_ts ~to_ts : Candle.t list =
  let batches = ref [] in
  let cur_to = ref to_ts in
  let max_iters = 200 in
  let iter = ref 0 in
  let continue = ref true in
  while !continue && !iter < max_iters do
    let batch = fetch ~from_ts ~to_ts:!cur_to in
    (match batch with
     | [] -> continue := false
     | c0 :: _ ->
       let oldest = c0.Candle.ts in
       batches := batch :: !batches;
       if Int64.compare oldest from_ts <= 0 then continue := false
       else if Int64.compare oldest !cur_to >= 0 then continue := false
       else cur_to := Int64.sub oldest 1L);
    incr iter
  done;
  let chrono = List.concat (List.rev !batches) in
  let seen = Hashtbl.create 4096 in
  List.filter (fun c ->
    if Hashtbl.mem seen c.Candle.ts then false
    else (Hashtbl.add seen c.Candle.ts (); true)
  ) chrono

let scalar_1 ind =
  match Indicators.Indicator.value ind with
  | Some (_, [v]) -> Some v
  | _ -> None

let bb_pct_b ind close =
  match Indicators.Indicator.value ind with
  | Some (_, [lower; _middle; upper]) ->
    let r = upper -. lower in
    if r = 0.0 then None else Some ((close -. lower) /. r)
  | _ -> None

let macd_hist_of ind =
  match Indicators.Indicator.value ind with
  | Some (_, [_macd; _signal; hist]) -> Some hist
  | _ -> None

(** Single-bar feature vector — same shape and order as
    [Strategies.Gbt_strategy.feature_names]. If any piece is still
    warming up (indicator returns [None] or the close-history ring
    is short of [lag_return_bars]) the whole row is [None]. *)
type feature_row = {
  rsi : float;
  mfi : float;
  bb_pct_b : float;
  macd_hist : float;
  volume_ratio : float;
  lag_return_5 : float;
  chaikin_osc : float;
  ad_slope_10 : float;
}

let lag_return_bars = 5
let ad_slope_bars = 10

(** Apply the GBT strategy's feature roster to every bar in [arr].
    Strict mirror of [Strategies.Gbt_strategy.on_candle]'s feature
    assembly — any drift between the two silently garbages the
    trained model. If you change one, change both. *)
let compute_features (arr : Candle.t array) : feature_row option array =
  let n = Array.length arr in
  let out = Array.make n None in
  let rsi_ = ref (Indicators.Rsi.make ~period:14) in
  let mfi_ = ref (Indicators.Mfi.make ~period:14) in
  let bb_  = ref (Indicators.Bollinger.make ~period:20 ~k:2.0 ()) in
  let macd_ = ref (Indicators.Macd.make ~fast:12 ~slow:26 ~signal:9 ()) in
  let vma_ = ref (Indicators.Volume_ma.make ~period:20) in
  let ad_ = ref (Indicators.Ad.make ()) in
  let chaikin_ = ref (Indicators.Chaikin_oscillator.make ~fast:3 ~slow:10 ()) in
  let close_ring_ =
    ref (Indicators.Ring.create ~capacity:lag_return_bars 0.0) in
  let ad_ring_ =
    ref (Indicators.Ring.create ~capacity:ad_slope_bars 0.0) in
  for i = 0 to n - 1 do
    let c = arr.(i) in
    rsi_ := Indicators.Indicator.update !rsi_ c;
    mfi_ := Indicators.Indicator.update !mfi_ c;
    bb_  := Indicators.Indicator.update !bb_ c;
    macd_ := Indicators.Indicator.update !macd_ c;
    vma_ := Indicators.Indicator.update !vma_ c;
    ad_  := Indicators.Indicator.update !ad_ c;
    chaikin_ := Indicators.Indicator.update !chaikin_ c;
    let close = Decimal.to_float c.Candle.close in
    let volume = Decimal.to_float c.Candle.volume in
    (* Read lag-return BEFORE pushing the current close — same
       ordering as [Gbt_strategy.on_candle]. *)
    let lag_opt =
      if Indicators.Ring.is_full !close_ring_ then
        let old = Indicators.Ring.oldest !close_ring_ in
        if old > 0.0 then Some (log (close /. old)) else None
      else None
    in
    close_ring_ := Indicators.Ring.push !close_ring_ close;
    let ad_slope_opt =
      match scalar_1 !ad_ with
      | None -> None
      | Some ad_now ->
        let slope =
          if Indicators.Ring.is_full !ad_ring_ then
            let old = Indicators.Ring.oldest !ad_ring_ in
            Some ((ad_now -. old) /. (Float.abs old +. 1.0))
          else None
        in
        ad_ring_ := Indicators.Ring.push !ad_ring_ ad_now;
        slope
    in
    let volume_ratio_opt =
      match scalar_1 !vma_ with
      | Some vma when vma > 0.0 -> Some (volume /. vma)
      | _ -> None
    in
    match
      scalar_1 !rsi_, scalar_1 !mfi_, bb_pct_b !bb_ close,
      macd_hist_of !macd_, volume_ratio_opt, lag_opt,
      scalar_1 !chaikin_, ad_slope_opt
    with
    | Some r, Some m, Some b, Some mh, Some vr, Some lr,
      Some co, Some ads ->
      out.(i) <- Some {
        rsi = r /. 100.0;
        mfi = m /. 100.0;
        bb_pct_b = b;
        macd_hist = mh;
        volume_ratio = vr;
        lag_return_5 = lr;
        chaikin_osc = co;
        ad_slope_10 = ads;
      }
    | _ -> ()
  done;
  out

let write_csv
    ~path
    ~horizon ~threshold
    (arr : Candle.t array)
    (feats : feature_row option array) =
  let n = Array.length arr in
  let oc = Out_channel.open_text path in
  Out_channel.output_string oc
    "ts,rsi,mfi,bb_pct_b,macd_hist,volume_ratio,lag_return_5,\
     chaikin_osc,ad_slope_10,label\n";
  let written = ref 0 in
  let skipped_warmup = ref 0 in
  for i = 0 to n - 1 - horizon do
    match feats.(i) with
    | None -> incr skipped_warmup
    | Some f ->
      let close_now = Decimal.to_float arr.(i).Candle.close in
      let close_future = Decimal.to_float arr.(i + horizon).Candle.close in
      let ret = (close_future -. close_now) /. close_now in
      let label =
        if ret > threshold then 2
        else if ret < -. threshold then 0
        else 1
      in
      Out_channel.output_string oc
        (Printf.sprintf "%Ld,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%d\n"
           arr.(i).Candle.ts
           f.rsi f.mfi f.bb_pct_b
           f.macd_hist f.volume_ratio f.lag_return_5
           f.chaikin_osc f.ad_slope_10
           label);
      incr written
  done;
  Out_channel.close oc;
  !written, !skipped_warmup

let () =
  let args = Array.to_list Sys.argv |> List.tl in
  let require_arg name =
    match arg_value name args with
    | Some v -> v
    | None ->
      Printf.eprintf "export-training-data: %s is required\n" name;
      usage ()
  in
  let broker_id = require_arg "--broker" in
  let symbol = require_arg "--symbol" in
  let output = require_arg "--output" in
  let instrument = Instrument.of_qualified symbol in
  let timeframe =
    match arg_value "--timeframe" args with
    | Some s -> Timeframe.of_string s
    | None -> Timeframe.H1
  in
  let now_ts = Int64.of_float (Unix.gettimeofday ()) in
  let to_ts = match arg_value "--to" args with
    | Some s -> parse_date s
    | None -> now_ts
  in
  let from_ts = match arg_value "--from" args with
    | Some s -> parse_date s
    | None -> Int64.sub to_ts (Int64.of_int (365 * 86400))
  in
  let horizon = match arg_value "--horizon" args with
    | Some v -> int_of_string v | None -> 5
  in
  let threshold = match arg_value "--threshold" args with
    | Some v -> float_of_string v | None -> 0.005
  in
  let prefix = broker_env_prefix broker_id in
  let secret = match arg_value "--secret" args with
    | Some v -> Some v
    | None -> Sys.getenv_opt (prefix ^ "_SECRET")
  in
  let account = match arg_value "--account" args with
    | Some v -> Some v
    | None -> Sys.getenv_opt (prefix ^ "_ACCOUNT_ID")
  in
  let client_id = match arg_value "--client-id" args with
    | Some v -> Some v
    | None -> Sys.getenv_opt "BCS_CLIENT_ID"
  in
  Eio_main.run @@ fun env ->
  Mirage_crypto_rng_unix.use_default ();
  let fetch ~from_ts ~to_ts =
    match broker_id with
    | "finam" ->
      let secret = match secret with
        | Some s -> s
        | None ->
          prerr_endline "finam requires --secret or FINAM_SECRET";
          exit 2
      in
      (match open_finam ~env ~secret ~account with
       | Opened_finam { rest; _ } ->
         Finam.Rest.bars rest ~from_ts ~to_ts ~n:9999
           ~instrument ~timeframe
       | _ -> assert false)
    | "bcs" ->
      (match open_bcs ~env ~secret ~account ~client_id with
       | Opened_bcs { rest; _ } ->
         Bcs.Rest.bars rest ~from_ts ~to_ts ~n:9999
           ~instrument ~timeframe
       | _ -> assert false)
    | other ->
      Printf.eprintf "unknown --broker: %s\n" other;
      exit 2
  in
  let candles = paginate_bars ~fetch ~from_ts ~to_ts in
  Printf.printf "Fetched %d bars from %s (%s)\n%!"
    (List.length candles) broker_id symbol;
  if candles = [] then exit 0;
  let arr = Array.of_list candles in
  let feats = compute_features arr in
  let written, skipped_warmup =
    write_csv ~path:output ~horizon ~threshold arr feats in
  Printf.printf
    "Wrote %d rows to %s (skipped %d warmup, %d tail bars w/o future)\n%!"
    written output skipped_warmup horizon
