open Core

let fp_inst =
  Instrument.make ~ticker:(Ticker.of_string "SBER") ~venue:(Mic.of_string "MISX") ()

let fp ~ts ~high ~low ~close ~delta : Footprint_bar.t =
  {
    Footprint_bar.instrument = fp_inst;
    ts = Int64.of_int ts;
    high = Decimal.of_float high;
    low = Decimal.of_float low;
    close = Decimal.of_float close;
    volume = Decimal.of_float 100.;
    delta = Decimal.of_float delta;
    poc_price = Decimal.of_float close;
  }

let build ?(lookback = 3) () =
  Strategies.Footprint_strategy.make
    (module Strategies.Cvd_divergence)
    { Strategies.Cvd_divergence.lookback }

let actions strat bars =
  let _, acts =
    List.fold_left
      (fun (s, acc) b ->
        let s', sig_ = Strategies.Footprint_strategy.on_footprint s fp_inst b in
        (s', sig_.Signal.action :: acc))
      (strat, []) bars
  in
  List.rev acts

let contains target acts = List.exists (fun a -> a = target) acts

(* Price climbs to a new window high while cumulative delta collapses —
   buyers not confirming the high: bearish divergence. *)
let bearish_series =
  [
    fp ~ts:0 ~high:100. ~low:99. ~close:100. ~delta:10.;
    fp ~ts:1 ~high:101. ~low:100. ~close:101. ~delta:10.;
    fp ~ts:2 ~high:102. ~low:101. ~close:102. ~delta:10.;
    fp ~ts:3 ~high:103. ~low:102. ~close:103. ~delta:(-50.);
  ]

(* Price drops to a new window low while cumulative delta surges up —
   sellers not confirming the low: bullish divergence. *)
let bullish_series =
  [
    fp ~ts:0 ~high:100. ~low:99. ~close:99.5 ~delta:(-10.);
    fp ~ts:1 ~high:99. ~low:98. ~close:98.5 ~delta:(-10.);
    fp ~ts:2 ~high:98. ~low:97. ~close:97.5 ~delta:(-10.);
    fp ~ts:3 ~high:97. ~low:96. ~close:96.5 ~delta:50.;
  ]

(* Price and cumulative delta rise together — the flow confirms the
   move, so there is no divergence and no entry. *)
let confirmed_uptrend =
  [
    fp ~ts:0 ~high:100. ~low:99. ~close:100. ~delta:10.;
    fp ~ts:1 ~high:101. ~low:100. ~close:101. ~delta:10.;
    fp ~ts:2 ~high:102. ~low:101. ~close:102. ~delta:10.;
    fp ~ts:3 ~high:103. ~low:102. ~close:103. ~delta:10.;
  ]

let test_bearish_divergence_enters_short () =
  let acts = actions (build ()) bearish_series in
  Alcotest.(check bool)
    "bearish divergence -> enter_short" true
    (contains Signal.Enter_short acts)

let test_bullish_divergence_enters_long () =
  let acts = actions (build ()) bullish_series in
  Alcotest.(check bool)
    "bullish divergence -> enter_long" true
    (contains Signal.Enter_long acts)

let test_confirmed_trend_holds () =
  let acts = actions (build ()) confirmed_uptrend in
  Alcotest.(check bool)
    "no short when delta confirms the high" true
    (not (contains Signal.Enter_short acts));
  Alcotest.(check bool)
    "no long either — flow confirms, does not diverge" true
    (not (contains Signal.Enter_long acts))

let test_rejects_tiny_lookback () =
  Alcotest.check_raises "lookback < 2 invalid"
    (Invalid_argument "Cvd_divergence: lookback must be >= 2") (fun () ->
      ignore (build ~lookback:1 ()))

let tests =
  [
    ("bearish divergence enters short", `Quick, test_bearish_divergence_enters_short);
    ("bullish divergence enters long", `Quick, test_bullish_divergence_enters_long);
    ("confirmed trend holds", `Quick, test_confirmed_trend_holds);
    ("rejects lookback < 2", `Quick, test_rejects_tiny_lookback);
  ]
