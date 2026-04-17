(** Tests for Logistic regression, Features, Trainer, and the
    Learned composite policy. *)

open Core
open Strategy_helpers

(** --- Logistic math --- *)

let test_sigmoid_bounds () =
  Alcotest.(check bool) "sigmoid(0) = 0.5"
    true (Float.abs (Logistic_regression.Logistic.sigmoid 0.0 -. 0.5) < 1e-9);
  Alcotest.(check bool) "sigmoid(large) → 1"
    true (Logistic_regression.Logistic.sigmoid 100.0 > 0.999);
  Alcotest.(check bool) "sigmoid(-large) → 0"
    true (Logistic_regression.Logistic.sigmoid (-100.0) < 0.001)

let test_predict_untrained_is_half () =
  let m = Logistic_regression.Logistic.make ~n_features:3 () in
  let p = Logistic_regression.Logistic.predict m [| 1.0; 2.0; 3.0 |] in
  Alcotest.(check bool) "untrained model predicts ~0.5"
    true (Float.abs (p -. 0.5) < 1e-9)

let test_sgd_converges () =
  let m = Logistic_regression.Logistic.make ~n_features:1 ~lr:0.5 () in
  let data = [
    [| 2.0 |], 1.0;  [| 3.0 |], 1.0;  [| 1.0 |], 1.0;
    [| -2.0 |], 0.0; [| -3.0 |], 0.0; [| -1.0 |], 0.0;
  ] in
  let _loss = Logistic_regression.Logistic.train m ~epochs:100 data in
  let p_pos = Logistic_regression.Logistic.predict m [| 5.0 |] in
  let p_neg = Logistic_regression.Logistic.predict m [| -5.0 |] in
  Alcotest.(check bool) "positive input → high P"
    true (p_pos > 0.8);
  Alcotest.(check bool) "negative input → low P"
    true (p_neg < 0.2)

let test_export_import () =
  let m = Logistic_regression.Logistic.make ~n_features:2 () in
  let data = [ [| 1.0; 0.0 |], 1.0; [| 0.0; 1.0 |], 0.0 ] in
  let _ = Logistic_regression.Logistic.train m ~epochs:50 data in
  let w = Logistic_regression.Logistic.export_weights m in
  let m2 = Logistic_regression.Logistic.of_weights w in
  let p1 = Logistic_regression.Logistic.predict m [| 1.0; 0.0 |] in
  let p2 = Logistic_regression.Logistic.predict m2 [| 1.0; 0.0 |] in
  Alcotest.(check (float 1e-9)) "exported model predicts same"
    p1 p2

(** --- Features --- *)

let test_features_shape () =
  let n = Logistic_regression.Features.n_features ~n_children:4 in
  Alcotest.(check int) "4 children → 10 features" 10 n

let test_features_extraction () =
  let inst = Instrument.make
    ~ticker:(Ticker.of_string "X") ~venue:(Mic.of_string "MISX") () in
  let mk_sig action strength = {
    Signal.ts = 0L; instrument = inst; action; strength;
    stop_loss = None; take_profit = None; reason = "" } in
  let signals = [
    mk_sig Signal.Enter_long 0.8;
    mk_sig Signal.Hold 0.0;
  ] in
  let candle = Candle.make ~ts:0L
    ~open_:(Decimal.of_float 100.0) ~high:(Decimal.of_float 101.0)
    ~low:(Decimal.of_float 99.0) ~close:(Decimal.of_float 100.5)
    ~volume:(Decimal.of_float 1000.0) in
  let f = Logistic_regression.Features.extract
    ~signals ~candle
    ~recent_closes:[100.0; 99.0; 101.0]
    ~recent_volumes:[800.0; 900.0; 1000.0] in
  Alcotest.(check int) "feature vector length"
    (Logistic_regression.Features.n_features ~n_children:2) (Array.length f);
  Alcotest.(check (float 1e-6)) "first child signal = +1"
    1.0 f.(0);
  Alcotest.(check (float 1e-6)) "first child strength"
    0.8 f.(1);
  Alcotest.(check (float 1e-6)) "second child signal = 0 (Hold)"
    0.0 f.(2)

(** --- Trainer --- *)

let test_trainer_smoke () =
  let children = [
    Strategies.Strategy.default (module Strategies.Sma_crossover);
    Strategies.Strategy.default (module Strategies.Rsi_mean_reversion);
  ] in
  let prices = List.init 200 (fun i ->
    50.0 +. 10.0 *. sin (float_of_int i /. 10.0)) in
  let candles = List.mapi (fun i p ->
    let px = Decimal.of_float p in
    Candle.make ~ts:(Int64.of_int (i * 60))
      ~open_:px ~high:px ~low:px ~close:px
      ~volume:(Decimal.of_int 100))
    prices in
  let result = Logistic_regression.Trainer.train
    ~children ~candles ~lookahead:5 ~epochs:5 () in
  Alcotest.(check bool) "produced weights"
    true (Array.length result.weights > 0);
  Alcotest.(check bool) "train_loss finite"
    true (Float.is_finite result.train_loss);
  Alcotest.(check bool) "has training samples"
    true (result.n_train > 0)

(** --- Learned composite policy (end-to-end) --- *)

(** Build a [Composite.predictor] from trained weights using the
    logistic regression modules. This is the glue between
    [logistic_regression] and [strategies] — lives in the test
    because production wiring would be in [bin/main.ml] or a
    dedicated application-layer module. *)
let make_predictor weights : Strategies.Composite.predictor =
  fun ~signals ~candle ~recent_closes ~recent_volumes ->
    let features = Logistic_regression.Features.extract
      ~signals ~candle ~recent_closes ~recent_volumes in
    let model = Logistic_regression.Logistic.of_weights weights in
    Logistic_regression.Logistic.predict model features

let test_learned_policy_smoke () =
  let children_build () = [
    Strategies.Strategy.default (module Strategies.Sma_crossover);
    Strategies.Strategy.default (module Strategies.Rsi_mean_reversion);
  ] in
  let prices = List.init 300 (fun i ->
    50.0 +. 15.0 *. sin (float_of_int i /. 8.0)) in
  let candles = List.mapi (fun i p ->
    let px = Decimal.of_float p in
    Candle.make ~ts:(Int64.of_int (i * 60))
      ~open_:px ~high:px ~low:px ~close:px
      ~volume:(Decimal.of_int 100))
    prices in
  let result = Logistic_regression.Trainer.train
    ~children:(children_build ()) ~candles ~lookahead:5 ~epochs:10 () in
  let predict = make_predictor result.weights in
  let strat = Strategies.Strategy.make (module Strategies.Composite)
    Strategies.Composite.{
      policy = Learned { predict; threshold = 0.6 };
      children = children_build ();
    } in
  let acts = actions_from_prices strat prices in
  let n_total = List.length acts in
  let n_hold = List.length (List.filter (fun a -> a = Signal.Hold) acts) in
  Alcotest.(check bool) "learned policy produces some signals"
    true (n_hold < n_total);
  Alcotest.(check bool) "learned policy doesn't signal every bar"
    true (n_hold > 0)

let tests = [
  "sigmoid bounds",           `Quick, test_sigmoid_bounds;
  "untrained predicts 0.5",   `Quick, test_predict_untrained_is_half;
  "SGD converges",            `Quick, test_sgd_converges;
  "export/import weights",    `Quick, test_export_import;
  "features shape",           `Quick, test_features_shape;
  "features extraction",      `Quick, test_features_extraction;
  "trainer smoke",            `Quick, test_trainer_smoke;
  "learned policy e2e",       `Quick, test_learned_policy_smoke;
]
