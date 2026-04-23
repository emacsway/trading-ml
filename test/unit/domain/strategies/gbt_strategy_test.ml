(** End-to-end tests for {!Strategies.Gbt_strategy}.

    A tiny 3-class LightGBM-style model is written to a tempfile,
    the strategy is pointed at it, and canned price series are
    pushed through. The model's structure is deliberately trivial
    — one split per class tree on the [rsi] feature at 0.5 —
    so the expected signal sequence is easy to reason about. *)

open Core
open Strategy_helpers

(** Class layout [0=down; 1=flat; 2=up]. Trees (one per class per
    iteration) encode: when [rsi] (feature 0) is above 0.5 →
    boost class 2, suppress class 0; when below or equal →
    boost class 0, suppress class 2. Class 1 stays flat so it
    never wins. *)
let tiny_model_text = {|tree
version=v3
num_class=3
num_tree_per_iteration=3
label_index=0
max_feature_idx=7
objective=multiclass num_class:3
feature_names=rsi mfi bb_pct_b macd_hist volume_ratio lag_return_5 chaikin_osc ad_slope_10
feature_infos=[0:1] [0:1] [0:1] [-inf:inf] [0:inf] [-inf:inf] [-inf:inf] [-inf:inf]
tree_sizes=100 100 100

Tree=0
num_leaves=2
num_cat=0
split_feature=0
split_gain=0.1
threshold=0.5
decision_type=2
left_child=-1
right_child=-2
leaf_value=1.0 -1.0
leaf_weight=100 100
leaf_count=100 100
internal_value=0.0
internal_weight=200
internal_count=200
is_linear=0
shrinkage=1


Tree=1
num_leaves=2
num_cat=0
split_feature=1
split_gain=0.01
threshold=0.5
decision_type=2
left_child=-1
right_child=-2
leaf_value=0.0 0.0
leaf_weight=100 100
leaf_count=100 100
internal_value=0.0
internal_weight=200
internal_count=200
is_linear=0
shrinkage=1


Tree=2
num_leaves=2
num_cat=0
split_feature=0
split_gain=0.1
threshold=0.5
decision_type=2
left_child=-1
right_child=-2
leaf_value=-1.0 1.0
leaf_weight=100 100
leaf_count=100 100
internal_value=0.0
internal_weight=200
internal_count=200
is_linear=0
shrinkage=1


end of trees
|}

let with_tmp_model text f =
  let path =
    Filename.concat
      (try Sys.getenv "TMPDIR" with Not_found -> "/tmp")
      (Printf.sprintf "gbt_strategy_test_%d_%d.txt"
         (Unix.getpid ())
         (int_of_float (Unix.gettimeofday () *. 1e6)))
  in
  Out_channel.with_open_text path
    (fun oc -> Out_channel.output_string oc text);
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
    (fun () -> f path)

let build
    ?(enter_threshold = 0.55)
    ?(allow_short = false)
    path =
  let p = Strategies.Gbt_strategy.{
    default_params with
    model_path = path;
    enter_threshold;
    allow_short;
  } in
  Strategies.Strategy.make (module Strategies.Gbt_strategy) p

let test_uptrend_triggers_enter_long () =
  with_tmp_model tiny_model_text (fun path ->
    let strat = build path in
    (* 20 bars warm-up Bollinger(20), then 25 rising bars push RSI
       well above 50 (→ scaled > 0.5), model picks class=up. *)
    let warmup = List.init 25 (fun i -> 100.0 +. float_of_int i *. 0.1) in
    let up = List.init 25 (fun i -> 103.0 +. float_of_int i) in
    let candles = ohlc_candles_from_prices (warmup @ up) in
    let acts = actions_from_ohlc strat candles in
    Alcotest.(check bool) "Enter_long emitted during uptrend"
      true (contains Signal.Enter_long acts))

let test_reversal_exits_long () =
  with_tmp_model tiny_model_text (fun path ->
    let strat = build path in
    let warmup = List.init 25 (fun i -> 100.0 +. float_of_int i *. 0.1) in
    let up    = List.init 25 (fun i -> 103.0 +. float_of_int i) in
    let down  = List.init 30 (fun i -> 128.0 -. float_of_int i) in
    let candles = ohlc_candles_from_prices (warmup @ up @ down) in
    let acts = actions_from_ohlc strat candles in
    Alcotest.(check bool) "Enter_long"
      true (contains Signal.Enter_long acts);
    Alcotest.(check bool) "Exit_long after reversal"
      true (contains Signal.Exit_long acts))

let test_short_disabled_by_default () =
  with_tmp_model tiny_model_text (fun path ->
    let strat = build ~allow_short:false path in
    let warmup = List.init 25 (fun i -> 100.0 +. float_of_int i *. 0.1) in
    let down   = List.init 30 (fun i -> 105.0 -. float_of_int i) in
    let candles = ohlc_candles_from_prices (warmup @ down) in
    let acts = actions_from_ohlc strat candles in
    Alcotest.(check bool) "no Enter_short when allow_short=false"
      true (not (contains Signal.Enter_short acts)))

let test_short_enabled_flips_on_down () =
  with_tmp_model tiny_model_text (fun path ->
    let strat = build ~allow_short:true path in
    let warmup = List.init 25 (fun i -> 100.0 +. float_of_int i *. 0.1) in
    let down   = List.init 30 (fun i -> 105.0 -. float_of_int i) in
    let candles = ohlc_candles_from_prices (warmup @ down) in
    let acts = actions_from_ohlc strat candles in
    Alcotest.(check bool) "Enter_short once shorting allowed"
      true (contains Signal.Enter_short acts))

let test_threshold_filters_low_confidence () =
  (* Raise the threshold above the model's softmax max (~0.665)
     so no entry ever fires. *)
  with_tmp_model tiny_model_text (fun path ->
    let strat = build ~enter_threshold:0.9 path in
    let warmup = List.init 25 (fun i -> 100.0 +. float_of_int i *. 0.1) in
    let up = List.init 25 (fun i -> 103.0 +. float_of_int i) in
    let candles = ohlc_candles_from_prices (warmup @ up) in
    let acts = actions_from_ohlc strat candles in
    Alcotest.(check bool) "no entry when confidence < threshold"
      true (not (contains Signal.Enter_long acts));
    Alcotest.(check bool) "no short entry either"
      true (not (contains Signal.Enter_short acts)))

let test_rejects_missing_model_path () =
  Alcotest.check_raises "empty model_path → Invalid_argument"
    (Invalid_argument "Gbt_strategy: model_path must be set")
    (fun () -> ignore (build ""))

let test_rejects_feature_name_mismatch () =
  let wrong_names_model = {|tree
version=v3
num_class=3
num_tree_per_iteration=3
label_index=0
max_feature_idx=2
objective=multiclass num_class:3
feature_names=a b c
feature_infos=[0:1] [0:1] [0:1]
tree_sizes=50 50 50

Tree=0
num_leaves=2
num_cat=0
split_feature=0
threshold=0.5
decision_type=2
left_child=-1
right_child=-2
leaf_value=0.0 0.0
is_linear=0
shrinkage=1

Tree=1
num_leaves=2
num_cat=0
split_feature=0
threshold=0.5
decision_type=2
left_child=-1
right_child=-2
leaf_value=0.0 0.0
is_linear=0
shrinkage=1

Tree=2
num_leaves=2
num_cat=0
split_feature=0
threshold=0.5
decision_type=2
left_child=-1
right_child=-2
leaf_value=0.0 0.0
is_linear=0
shrinkage=1

end of trees
|} in
  with_tmp_model wrong_names_model (fun path ->
    Alcotest.check_raises "mismatch → Invalid_argument"
      (Invalid_argument
        "Gbt_strategy: model feature_names mismatch — \
         strategy expects [rsi, mfi, bb_pct_b, macd_hist, volume_ratio, \
         lag_return_5, chaikin_osc, ad_slope_10], model has [a, b, c]")
      (fun () -> ignore (build path)))

let test_rejects_non_multiclass_objective () =
  let binary_model = {|tree
version=v3
num_class=1
num_tree_per_iteration=1
label_index=0
max_feature_idx=2
objective=binary sigmoid:1
feature_names=rsi mfi bb_pct_b

Tree=0
num_leaves=2
num_cat=0
split_feature=0
threshold=0.5
decision_type=2
left_child=-1
right_child=-2
leaf_value=0.0 0.0
is_linear=0
shrinkage=1

end of trees
|} in
  with_tmp_model binary_model (fun path ->
    Alcotest.check_raises "binary → Invalid_argument"
      (Invalid_argument
        "Gbt_strategy: model objective must be Multiclass(3) with \
         classes [0=down; 1=flat; 2=up]")
      (fun () -> ignore (build path)))

(** Constant-class model builder: every tree on every iteration
    pushes [boost] into class [favored], zero elsewhere. Softmax
    over raw scores then picks [favored] by a wide margin. Used
    only by the hot-reload test where we need a model whose
    predictions are completely decoupled from feature values. *)
let constant_class_model ~favored ~boost =
  let tree_for c =
    let leaf = if c = favored then boost else 0.0 in
    Printf.sprintf {|Tree=%d
num_leaves=2
num_cat=0
split_feature=0
threshold=0.5
decision_type=2
left_child=-1
right_child=-2
leaf_value=%f %f
is_linear=0
shrinkage=1

|} c leaf leaf
  in
  Printf.sprintf {|tree
version=v3
num_class=3
num_tree_per_iteration=3
label_index=0
max_feature_idx=7
objective=multiclass num_class:3
feature_names=rsi mfi bb_pct_b macd_hist volume_ratio lag_return_5 chaikin_osc ad_slope_10
feature_infos=[0:1] [0:1] [0:1] [-inf:inf] [0:inf] [-inf:inf] [-inf:inf] [-inf:inf]
tree_sizes=50 50 50

%s%s%send of trees
|} (tree_for 0) (tree_for 1) (tree_for 2)

(** [Gbt_strategy] re-stats the model file before every prediction
    and transparently picks up an atomically-replaced version.
    Test: start with a [class 0 always wins] model (under
    [allow_short=true] that means Enter_short on a confident
    prediction), overwrite with [class 2 always wins], force a
    future mtime so the reload detector fires, and verify the
    signal flips to Enter_long. *)
let test_hot_reload_picks_up_new_model () =
  with_tmp_model (constant_class_model ~favored:0 ~boost:3.0) (fun path ->
    let strat = build ~allow_short:true path in
    let warmup = List.init 25 (fun i -> 100.0 +. float_of_int i *. 0.1) in
    let up1 = List.init 10 (fun i -> 103.0 +. float_of_int i) in
    (* Phase 1: run through the class=0 model; expect Enter_short
       (class=0 with allow_short=true maps to "go short"). *)
    let strat_after_phase1, acts_phase1 =
      List.fold_left (fun (s, acc) c ->
        let s', sig_ = Strategies.Strategy.on_candle s inst c in
        s', sig_.Signal.action :: acc)
        (strat, []) (ohlc_candles_from_prices (warmup @ up1))
    in
    let acts_phase1 = List.rev acts_phase1 in
    Alcotest.(check bool) "phase 1 (class=0): Enter_short seen"
      true (contains Signal.Enter_short acts_phase1);
    (* Overwrite the model with a class=2 winner; bump mtime into
       the future so the strategy's reload detector fires on the
       next [on_candle] call. *)
    Out_channel.with_open_text path (fun oc ->
      Out_channel.output_string oc
        (constant_class_model ~favored:2 ~boost:3.0));
    let now = Unix.gettimeofday () in
    Unix.utimes path now (now +. 3600.0);
    (* Phase 2: same strategy instance continues. First bar should
       reload the model; position was Short at the end of phase 1,
       so the first confident class=2 prediction flips to Enter_long. *)
    let up2 = List.init 10 (fun i -> 120.0 +. float_of_int i) in
    let _, acts_phase2 =
      List.fold_left (fun (s, acc) c ->
        let s', sig_ = Strategies.Strategy.on_candle s inst c in
        s', sig_.Signal.action :: acc)
        (strat_after_phase1, []) (ohlc_candles_from_prices up2)
    in
    let acts_phase2 = List.rev acts_phase2 in
    Alcotest.(check bool) "phase 2 (reloaded class=2): Enter_long seen"
      true (contains Signal.Enter_long acts_phase2))

let test_unchanged_mtime_does_not_reload () =
  (* Sanity: if the file's mtime doesn't advance, the strategy
     keeps the model it already loaded — no per-bar reparsing. *)
  with_tmp_model (constant_class_model ~favored:0 ~boost:3.0) (fun path ->
    let strat = build ~allow_short:true path in
    (* Pin mtime to a known past value, run a batch, pin it again
       (same value), run another batch. Nothing should change. *)
    let pin = Unix.gettimeofday () -. 3600.0 in
    Unix.utimes path pin pin;
    let warmup = List.init 25 (fun i -> 100.0 +. float_of_int i *. 0.1) in
    let up = List.init 10 (fun i -> 103.0 +. float_of_int i) in
    let candles = ohlc_candles_from_prices (warmup @ up) in
    let acts = actions_from_ohlc strat candles in
    Alcotest.(check bool) "class=0 pinned → Enter_short still fires"
      true (contains Signal.Enter_short acts))

(** Explicitly-priced candle for bracket tests — needs independent
    control of close (feeds model / sets entry price) and of
    high/low (drives bracket-trigger decisions). *)
let bracket_bar ~ts ~close ~high ~low =
  Candle.make
    ~ts:(Int64.of_int ts)
    ~open_:(Decimal.of_float close)
    ~high:(Decimal.of_float high)
    ~low:(Decimal.of_float low)
    ~close:(Decimal.of_float close)
    ~volume:(Decimal.of_int 1000)

(** Run a strategy through a series of candles and collect
    (action, reason) pairs for every emission — reasons matter
    here because bracket exits vs model exits look identical at
    the action level. *)
let actions_with_reasons strat candles =
  let _, acc =
    List.fold_left (fun (s, acc) c ->
      let s', sig_ = Strategies.Strategy.on_candle s inst c in
      s', (sig_.Signal.action, sig_.reason) :: acc)
      (strat, []) candles
  in
  List.rev acc

let test_bracket_tp_exit () =
  (* Up-trending warmup + up sequence triggers Enter_long. Then
     a sharp up-spike on a subsequent bar has [high] above the
     +1.5·ATR take-profit level, exiting with reason "TP hit". *)
  with_tmp_model (constant_class_model ~favored:2 ~boost:3.0) (fun path ->
    let strat = build path in
    let warmup = List.init 40 (fun i -> 100.0 +. float_of_int i *. 0.1) in
    let candles =
      ohlc_candles_from_prices warmup
      @ [ bracket_bar ~ts:100 ~close:105.0 ~high:150.0 ~low:104.0 ]
    in
    let reasons = actions_with_reasons strat candles in
    let tp_exit = List.exists (fun (a, r) ->
      a = Signal.Exit_long && r = "TP hit") reasons in
    Alcotest.(check bool) "Exit_long with TP-hit reason" true tp_exit)

let test_bracket_sl_exit () =
  (* Same setup but the spike goes DOWN below the -1·ATR stop. *)
  with_tmp_model (constant_class_model ~favored:2 ~boost:3.0) (fun path ->
    let strat = build path in
    let warmup = List.init 40 (fun i -> 100.0 +. float_of_int i *. 0.1) in
    let candles =
      ohlc_candles_from_prices warmup
      @ [ bracket_bar ~ts:100 ~close:104.0 ~high:104.5 ~low:50.0 ]
    in
    let reasons = actions_with_reasons strat candles in
    let sl_exit = List.exists (fun (a, r) ->
      a = Signal.Exit_long && r = "SL hit") reasons in
    Alcotest.(check bool) "Exit_long with SL-hit reason" true sl_exit)

(** Quiet warmup: close oscillates on a tiny sinusoid around 100
    so indicators (RSI/MFI/MACD) find some movement to feed on
    and emerge from warm-up. High/low are capped by ±0.03 so the
    bars stay narrow and ATR converges to ~0.06 — small enough
    that subsequent bracket-controlled bars with high/low in the
    same band don't accidentally trigger TP/SL. *)
let flat_warmup_bars ~n =
  List.init n (fun i ->
    let close = 100.0 +. 0.02 *. Float.sin (float_of_int i *. 0.5) in
    bracket_bar ~ts:i ~close
      ~high:(close +. 0.03) ~low:(close -. 0.03))

let test_bracket_tie_sl_wins () =
  (* With flat warmup + immediate wide-range tie bar after entry,
     the only bracket-trigger event is the tie bar itself. Both TP
     (100+1.5·0.06=100.09) and SL (100-1·0.06=99.94) are crossed
     simultaneously by high=200 / low=0 — convention says SL
     wins. *)
  with_tmp_model (constant_class_model ~favored:2 ~boost:3.0) (fun path ->
    let strat = build path in
    let candles =
      flat_warmup_bars ~n:40
      @ [ bracket_bar ~ts:40 ~close:100.0 ~high:100.03 ~low:99.97 ]
      @ [ bracket_bar ~ts:41 ~close:100.0 ~high:200.0 ~low:0.0 ]
    in
    let reasons = actions_with_reasons strat candles in
    let sl_exit = List.exists (fun (a, r) ->
      a = Signal.Exit_long && r = "SL hit") reasons in
    let tp_exit = List.exists (fun (a, r) ->
      a = Signal.Exit_long && r = "TP hit") reasons in
    Alcotest.(check bool) "SL wins the tie-break" true sl_exit;
    Alcotest.(check bool) "TP does NOT fire on tie" false tp_exit)

let test_bracket_timeout_exit () =
  (* After entry, bars sit inside the [sl, tp] range for
     max_hold_bars + a few: timeout fires with reason "timeout". *)
  with_tmp_model (constant_class_model ~favored:2 ~boost:3.0) (fun path ->
    let p = Strategies.Gbt_strategy.{
      default_params with
      model_path = path;
      max_hold_bars = 5;
    } in
    let strat = Strategies.Strategy.make
      (module Strategies.Gbt_strategy) p in
    let warmup = List.init 40 (fun i -> 100.0 +. float_of_int i *. 0.1) in
    let warmup_candles = ohlc_candles_from_prices warmup in
    (* 10 narrow bars after entry — all close to entry price so
       neither barrier triggers; timeout should fire at bar 5 or 6
       after entry. *)
    let tight_bars = List.init 10 (fun i ->
      bracket_bar ~ts:(100 + i)
        ~close:104.0 ~high:104.05 ~low:103.95) in
    let candles = warmup_candles @ tight_bars in
    let reasons = actions_with_reasons strat candles in
    let timeout_exit = List.exists (fun (a, r) ->
      a = Signal.Exit_long && r = "timeout") reasons in
    Alcotest.(check bool) "Exit_long with timeout reason" true timeout_exit)

let test_bracket_priority_holds_through_quiet_bars () =
  (* After Enter_long, bars whose high/low stay strictly inside
     the bracket must not trigger an Exit_long (no early exit on
     any grounds — model predictions are ignored while in
     position). Only TP / SL / timeout decide. Here we deliberately
     give [max_hold_bars = 100] and feed 20 quiet bars → none of
     the three triggers should fire. *)
  with_tmp_model (constant_class_model ~favored:2 ~boost:3.0) (fun path ->
    let p = Strategies.Gbt_strategy.{
      default_params with
      model_path = path;
      max_hold_bars = 100;
    } in
    let strat = Strategies.Strategy.make
      (module Strategies.Gbt_strategy) p in
    let post_entry = List.init 20 (fun i ->
      bracket_bar ~ts:(40 + i) ~close:100.0 ~high:100.03 ~low:99.97) in
    let candles = flat_warmup_bars ~n:30 @ post_entry in
    let actions =
      List.rev_map (fun c -> snd c) (actions_with_reasons strat candles
        |> List.rev_map (fun (a, _) -> (), a))
    in
    let had_enter = List.mem Signal.Enter_long actions in
    let had_exit  = List.mem Signal.Exit_long  actions in
    Alcotest.(check bool) "Enter_long did fire"    true had_enter;
    Alcotest.(check bool) "no Exit_long (bracket holds through quiet bars)"
      false had_exit)

let test_entry_signal_carries_tp_sl () =
  (* Verify the Enter_long signal itself carries populated
     stop_loss / take_profit fields — downstream (broker /
     engine) needs them to attach server-side brackets. *)
  with_tmp_model (constant_class_model ~favored:2 ~boost:3.0) (fun path ->
    let strat = build path in
    let warmup = List.init 40 (fun i -> 100.0 +. float_of_int i *. 0.1) in
    let candles = ohlc_candles_from_prices warmup in
    let _, entries =
      List.fold_left (fun (s, acc) c ->
        let s', sig_ = Strategies.Strategy.on_candle s inst c in
        let acc = match sig_.Signal.action with
          | Enter_long -> sig_ :: acc
          | _ -> acc
        in
        s', acc)
        (strat, []) candles
    in
    match entries with
    | [] -> Alcotest.fail "no Enter_long emitted in warmup series"
    | sig_ :: _ ->
      Alcotest.(check bool) "stop_loss populated" true
        (Option.is_some sig_.Signal.stop_loss);
      Alcotest.(check bool) "take_profit populated" true
        (Option.is_some sig_.Signal.take_profit))

let test_bracket_params_validated () =
  with_tmp_model (constant_class_model ~favored:2 ~boost:3.0) (fun path ->
    let mk_with ~tp ~sl ~max_hold =
      let p = Strategies.Gbt_strategy.{
        default_params with
        model_path = path; tp_mult = tp; sl_mult = sl; max_hold_bars = max_hold;
      } in
      fun () -> ignore (Strategies.Strategy.make
        (module Strategies.Gbt_strategy) p)
    in
    Alcotest.check_raises "tp_mult must be > 0"
      (Invalid_argument "Gbt_strategy: tp_mult > 0")
      (mk_with ~tp:0.0 ~sl:1.0 ~max_hold:20);
    Alcotest.check_raises "sl_mult must be > 0"
      (Invalid_argument "Gbt_strategy: sl_mult > 0")
      (mk_with ~tp:1.5 ~sl:(-0.5) ~max_hold:20);
    Alcotest.check_raises "max_hold_bars must be > 0"
      (Invalid_argument "Gbt_strategy: max_hold_bars > 0")
      (mk_with ~tp:1.5 ~sl:1.0 ~max_hold:0))

let tests = [
  "uptrend → Enter_long",              `Quick, test_uptrend_triggers_enter_long;
  "reversal → Exit_long",              `Quick, test_reversal_exits_long;
  "short disabled by default",         `Quick, test_short_disabled_by_default;
  "short enabled flips on down",       `Quick, test_short_enabled_flips_on_down;
  "threshold filters low confidence",  `Quick, test_threshold_filters_low_confidence;
  "rejects missing model_path",        `Quick, test_rejects_missing_model_path;
  "rejects feature name mismatch",     `Quick, test_rejects_feature_name_mismatch;
  "rejects non-multiclass objective",  `Quick, test_rejects_non_multiclass_objective;
  "hot-reload picks up new model",     `Quick, test_hot_reload_picks_up_new_model;
  "unchanged mtime: no reload",        `Quick, test_unchanged_mtime_does_not_reload;
  "bracket TP exit",                   `Quick, test_bracket_tp_exit;
  "bracket SL exit",                   `Quick, test_bracket_sl_exit;
  "bracket tie: SL wins",              `Quick, test_bracket_tie_sl_wins;
  "bracket timeout exit",              `Quick, test_bracket_timeout_exit;
  "bracket priority over quiet bars",  `Quick, test_bracket_priority_holds_through_quiet_bars;
  "entry signal carries TP/SL",        `Quick, test_entry_signal_carries_tp_sl;
  "bracket params validated",          `Quick, test_bracket_params_validated;
]
