(** Live smoke tests against the real Alor Trade API.

    Skipped silently when credentials are absent so the file can live
    in the tree without tripping CI. Run manually during a session with:

    {v
    export ALOR_SECRET=<refresh token from the Alor dev portal>
    export ALOR_PORTFOLIO=<portfolio code, e.g. D12345>
    dune build @live_smoke
    v}

    Alor assigns the order id itself ([orderNumber]); there is no
    caller-supplied client-order-id. The lifecycle test places a
    far-from-market limit BUY, then resolves / cancels it by that
    server-assigned id. *)

open Core

let portfolio () = Sys.getenv_opt "ALOR_PORTFOLIO"
let refresh_token () = Sys.getenv_opt "ALOR_SECRET"

let skip_unless_creds () =
  match (refresh_token (), portfolio ()) with
  | Some r, Some p when r <> "" && p <> "" -> (r, p)
  | _ ->
      Printf.printf "  [SKIP] ALOR_SECRET / ALOR_PORTFOLIO not set\n%!";
      raise Exit

let make_rest ~env ~refresh_token ~portfolio =
  let cfg = Alor.Config.make ~refresh_token ~portfolio () in
  let transport = Http_transport.make_eio ~env in
  Alor.Rest.make ~transport ~cfg

let sber =
  Instrument.make ~ticker:(Ticker.of_string "SBER") ~venue:(Mic.of_string "MISX")
    ~board:(Board.of_string "TQBR") ()

(** Baseline: auth round-trip works, bars decode, and the
    current-session trades list decodes even on an idle account. *)
let test_auth_bars_trades () =
  try
    let refresh_token, portfolio = skip_unless_creds () in
    Eio_main.run @@ fun env ->
    Mirage_crypto_rng_unix.use_default ();
    let rest = make_rest ~env ~refresh_token ~portfolio in
    let bars = Alor.Rest.bars rest ~n:10 ~instrument:sber ~timeframe:Timeframe.H1 in
    Alcotest.(check bool) "got at least one bar" true (List.length bars > 0);
    let trades = Alor.Rest.get_trades rest ~exchange:"MOEX" in
    Printf.printf "  [info] %d trades this session\n%!" (List.length trades)
  with Exit -> ()

(** Full order lifecycle: place a 1-lot limit BUY well below market →
    resolve by orderNumber → cancel (in [finally] so it runs even if an
    assert fails). *)
let test_limit_order_lifecycle () =
  try
    let refresh_token, portfolio = skip_unless_creds () in
    Eio_main.run @@ fun env ->
    Mirage_crypto_rng_unix.use_default ();
    let rest = make_rest ~env ~refresh_token ~portfolio in
    let bars = Alor.Rest.bars rest ~n:1 ~instrument:sber ~timeframe:Timeframe.H1 in
    let last_close =
      match List.rev bars with
      | c :: _ -> Decimal.to_float c.Candle.close
      | [] -> failwith "no bars to anchor limit price"
    in
    let snap px = Decimal.of_float (Float.round (px *. 100.0) /. 100.0) in
    Printf.printf "  [info] last H1 close = %.2f\n%!" last_close;
    let order_id =
      Alor.Rest.place_order rest ~instrument:sber ~side:Side.Buy ~quantity:1
        ~kind:(Order.Limit (snap (last_close *. 0.95)))
        ~tif:Order.DAY ~comment:"alor-smoke"
    in
    Printf.printf "  [info] placed orderNumber=%s\n%!" order_id;
    Fun.protect
      ~finally:(fun () ->
        try Alor.Rest.cancel_order rest ~exchange:"MOEX" ~order_id
        with e ->
          Printf.printf "  [warn] cancel failed for %s: %s\n%!" order_id
            (Printexc.to_string e))
      (fun () ->
        let fetched = Alor.Rest.get_order rest ~exchange:"MOEX" ~order_id in
        Alcotest.(check string) "round-trip order_id on get" order_id fetched.order_id;
        Printf.printf "  [info] fetched status=%s\n%!"
          (Order.status_to_string fetched.status))
  with Exit -> ()

let tests =
  [
    ("auth + bars + trades", `Quick, test_auth_bars_trades);
    ("limit order lifecycle", `Quick, test_limit_order_lifecycle);
  ]
