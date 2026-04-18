(** Historical replay driver over {!Step}. Folds the shared
    state machine over a candle list, collecting fills and a
    mark-to-market equity curve, then aggregates return / drawdown.

    All the trade-sizing, risk-gating and portfolio-update logic
    lives in {!Step.execute_pending} / {!Step.advance_strategy} —
    {!Live_engine} drives the same primitives on streaming bars,
    so paper P&L converges with a backtest over identical data. *)

open Core

type fill = {
  ts : int64;
  instrument : Instrument.t;
  side : Side.t;
  quantity : Decimal.t;
  price : Decimal.t;
  fee : Decimal.t;
  reason : string;
}

type result = {
  final : Portfolio.t;
  fills : fill list;
  equity_curve : (int64 * Decimal.t) list;
  max_drawdown : float;
  total_return : float;
  num_trades : int;
}

type config = {
  initial_cash : Decimal.t;
  fee_rate : float;
  limits : Risk.limits;
}

let default_config ?(initial_cash = Decimal.of_int 1_000_000) () =
  { initial_cash; fee_rate = 0.0005;
    limits = Risk.default_limits ~equity:initial_cash }

let max_drawdown equity_curve =
  match equity_curve with
  | [] -> 0.0
  | (_, first) :: _ ->
    let peak = ref (Decimal.to_float first) in
    let max_dd = ref 0.0 in
    List.iter (fun (_, eq) ->
      let e = Decimal.to_float eq in
      if e > !peak then peak := e;
      if !peak > 0.0 then
        let dd = (!peak -. e) /. !peak in
        if dd > !max_dd then max_dd := dd
    ) equity_curve;
    !max_dd

(** One bar through the shared state machine: executes any pending
    signal at [c.open_], captures an optional fill and a marked-to-close
    equity point, then advances the strategy for the next bar. Pure. *)
let tick_step step_cfg instrument (state : Step.state) (c : Candle.t)
  : Step.state * (fill option * (int64 * Decimal.t)) =
  let state1, fill_opt = Step.execute_pending step_cfg state c in
  let fill = Option.map (fun ((sig_ : Signal.t), (s : Step.settled)) ->
    { ts = sig_.ts; instrument; side = s.side;
      quantity = s.quantity; price = s.price; fee = s.fee;
      reason = sig_.reason }) fill_opt in
  let mark _ = Some c.Candle.close in
  let eq = Portfolio.equity state1.portfolio mark in
  let state2 = Step.advance_strategy step_cfg state1 c in
  state2, (fill, (c.ts, eq))

let run
    ~(config : config)
    ~(strategy : Strategies.Strategy.t)
    ~(instrument : Instrument.t)
    ~(candles : Candle.t list) : result =
  let step_cfg : Step.config = {
    limits = config.limits;
    instrument;
    fee_rate = config.fee_rate;
  } in
  let init = Step.make_state ~strategy ~cash:config.initial_cash in
  (* Fold the shared state machine over the candle stream. Accumulator
     is (state, fills-newest-first, equity_curve-newest-first) —
     identical shape to Live_engine's streaming loop, just driven
     synchronously over a list instead of an Eio source. *)
  let final_state, fills_rev, eq_curve_rev =
    candles
    |> Stream.of_list
    |> Stream.fold_left
      (fun (state, fills, eq_curve) c ->
        let state', (fill_opt, eq_point) =
          tick_step step_cfg instrument state c in
        let fills' = match fill_opt with
          | Some f -> f :: fills
          | None -> fills
        in
        state', fills', eq_point :: eq_curve)
      (init, [], [])
  in
  let equity_curve = List.rev eq_curve_rev in
  let fills = List.rev fills_rev in
  let total_return =
    let init_c = Decimal.to_float config.initial_cash in
    let fin = Portfolio.equity final_state.portfolio (fun _ -> None)
              |> Decimal.to_float in
    if init_c = 0.0 then 0.0 else (fin -. init_c) /. init_c
  in
  {
    final = final_state.portfolio;
    fills;
    equity_curve;
    max_drawdown = max_drawdown equity_curve;
    total_return;
    num_trades = List.length fills;
  }
