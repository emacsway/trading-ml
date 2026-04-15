open Core

let candle close =
  Candle.make ~ts:0L
    ~open_:(Decimal.of_float close)
    ~high:(Decimal.of_float close)
    ~low:(Decimal.of_float close)
    ~close:(Decimal.of_float close)
    ~volume:(Decimal.of_int 1)

let feed indicator closes =
  List.fold_left (fun ind c -> Indicators.Indicator.update ind (candle c))
    indicator closes

let scalar ind =
  match Indicators.Indicator.value ind with
  | Some (_, [v]) -> v
  | _ -> Float.nan

let test_sma () =
  let ind = Indicators.Sma.make ~period:3 in
  let ind = feed ind [1.0; 2.0; 3.0] in
  Alcotest.(check (float 1e-9)) "sma 1,2,3" 2.0 (scalar ind);
  let ind = feed ind [10.0] in
  Alcotest.(check (float 1e-9)) "sma window slides" 5.0 (scalar ind)

let test_sma_partial () =
  let ind = Indicators.Sma.make ~period:5 in
  let ind = feed ind [1.0; 2.0] in
  Alcotest.(check bool) "not enough data" true
    (Indicators.Indicator.value ind = None)

let test_ema_converges () =
  let ind = Indicators.Ema.make ~period:5 in
  (* Feed constant 10 — EMA must converge to 10 *)
  let ind = feed ind (List.init 50 (fun _ -> 10.0)) in
  Alcotest.(check (float 1e-6)) "ema const" 10.0 (scalar ind)

let test_rsi_extremes () =
  (* Monotonically rising → RSI = 100 *)
  let ind = Indicators.Rsi.make ~period:14 in
  let ind = feed ind (List.init 30 (fun i -> float_of_int (i + 1))) in
  let v = scalar ind in
  Alcotest.(check bool) (Printf.sprintf "rsi up ~ 100 (got %.3f)" v) true
    (v > 99.9)

let test_bollinger_constants () =
  (* Constant prices → σ = 0, upper = middle = lower *)
  let ind = Indicators.Bollinger.make ~period:20 ~k:2.0 () in
  let ind = feed ind (List.init 25 (fun _ -> 50.0)) in
  match Indicators.Indicator.value ind with
  | Some (_, [l; m; u]) ->
    Alcotest.(check (float 1e-6)) "lower=middle" m l;
    Alcotest.(check (float 1e-6)) "upper=middle" m u;
    Alcotest.(check (float 1e-6)) "middle=50" 50.0 m
  | _ -> Alcotest.fail "no value"

let test_macd_runs () =
  let ind = Indicators.Macd.make ~fast:3 ~slow:6 ~signal:2 () in
  let ind = feed ind (List.init 30 (fun i ->
    50.0 +. sin (float_of_int i /. 3.0) *. 5.0))
  in
  match Indicators.Indicator.value ind with
  | Some (_, [_; _; _]) -> ()
  | _ -> Alcotest.fail "macd produced no value"

let tests = [
  "sma basic", `Quick, test_sma;
  "sma partial", `Quick, test_sma_partial;
  "ema converges", `Quick, test_ema_converges;
  "rsi uptrend extreme", `Quick, test_rsi_extremes;
  "bollinger constants", `Quick, test_bollinger_constants;
  "macd produces output", `Quick, test_macd_runs;
]
