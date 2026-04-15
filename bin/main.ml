(** CLI entry point.
    Subcommands:
      trading serve [--port 8080]        — start HTTP API server
      trading list                        — print indicators and strategies
      trading backtest <strategy> [--n N] — run one backtest and print summary *)

open Core

let usage () =
  prerr_endline {|trading <command> [options]

  serve [--port 8080]
      start HTTP API server (bound to localhost)

  list
      show registered indicators and strategies

  backtest <strategy> [--n N] [--symbol SBER]
      run a backtest on synthetic data and print summary
|};
  exit 2

let cmd_list () =
  print_endline "Indicators:";
  List.iter (fun s -> Printf.printf "  - %s\n" s.Indicators.Registry.name)
    Indicators.Registry.specs;
  print_endline "Strategies:";
  List.iter (fun s -> Printf.printf "  - %s\n" s.Strategies.Registry.name)
    Strategies.Registry.specs

let cmd_backtest args =
  let strat_name = match args with
    | n :: _ -> n | [] -> usage () in
  let n =
    let rec find = function
      | "--n" :: v :: _ -> int_of_string v
      | _ :: rest -> find rest
      | [] -> 500
    in find args in
  let symbol =
    let rec find = function
      | "--symbol" :: v :: _ -> Symbol.of_string v
      | _ :: rest -> find rest
      | [] -> Symbol.of_string "SBER"
    in find args in
  match Strategies.Registry.find strat_name with
  | None ->
    Printf.eprintf "unknown strategy %s\n" strat_name;
    exit 1
  | Some spec ->
    let strat = spec.build [] in
    let candles = Server.Synthetic.generate
      ~n ~start_ts:1_704_067_200L ~tf_seconds:3600 ~start_price:100.0 in
    let cfg = Engine.Backtest.default_config () in
    let r = Engine.Backtest.run ~config:cfg ~strategy:strat ~symbol ~candles in
    Printf.printf "Strategy: %s\nBars: %d\nTrades: %d\n\
                   Total return: %.2f%%\nMax drawdown: %.2f%%\n\
                   Realized PnL: %s\nFinal cash: %s\n"
      strat_name n r.num_trades
      (r.total_return *. 100.0) (r.max_drawdown *. 100.0)
      (Decimal.to_string r.final.realized_pnl)
      (Decimal.to_string r.final.cash)

let cmd_serve args =
  let port =
    let rec find = function
      | "--port" :: v :: _ -> int_of_string v
      | _ :: rest -> find rest
      | [] -> 8080
    in find args in
  Eio_main.run @@ fun env ->
  Printf.printf "trading: listening on http://127.0.0.1:%d\n%!" port;
  Server.Http.run ~env ~port

let () =
  match Array.to_list Sys.argv with
  | _ :: "list" :: _ -> cmd_list ()
  | _ :: "backtest" :: rest -> cmd_backtest rest
  | _ :: "serve" :: rest -> cmd_serve rest
  | _ -> usage ()
