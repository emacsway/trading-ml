(** Unit tests for [Alor.Rest]: history decoding + request shape, and
    order placement (endpoint selection, body, idempotency header,
    orderNumber extraction). The scripted transport answers the OAuth
    [/refresh] exchange first, then captures the real request. *)

open Core
open Alor

let make_cfg () =
  Config.make
    ~api_base:(Uri.of_string "https://api.test")
    ~oauth_base:(Uri.of_string "https://oauth.test")
    ~refresh_token:"R" ~portfolio:"D12345" ()

(** First call → token exchange ([AccessToken]); subsequent calls →
    [data_response], captured for assertions. *)
let scripted ~data_response : Http_transport.t * Http_transport.request ref =
  let captured =
    ref { Http_transport.meth = `GET; url = Uri.empty; headers = []; body = None }
  in
  let count = ref 0 in
  let t : Http_transport.t =
   fun req ->
    incr count;
    if !count = 1 then
      {
        status = 200;
        body = Yojson.Safe.to_string (`Assoc [ ("AccessToken", `String "ACCESS") ]);
      }
    else begin
      captured := req;
      { status = 200; body = data_response }
    end
  in
  (t, captured)

let history_response =
  {|{ "history": [
       { "time": 1714557600, "open": 319.0, "high": 320.0, "low": 318.8, "close": 319.5, "volume": 1800 },
       { "time": 1714561200, "open": 319.5, "high": 321.0, "low": 319.5, "close": 320.5, "volume": 1500 }
     ], "next": 1714561200, "prev": 1714554000 }|}

let sber =
  Instrument.make ~ticker:(Ticker.of_string "SBER") ~venue:(Mic.of_string "MISX")
    ~board:(Board.of_string "TQBR") ()

let test_bars_request_and_decode () =
  let t, captured = scripted ~data_response:history_response in
  let rest = Rest.make ~transport:t ~cfg:(make_cfg ()) in
  let bars = Rest.bars rest ~n:100 ~instrument:sber ~timeframe:H1 in
  let req = !captured in
  Alcotest.(check bool) "GET" true (req.meth = `GET);
  Alcotest.(check string) "path" "/md/v2/history" (Uri.path req.url);
  let qp n = Option.value (Uri.get_query_param req.url n) ~default:"<missing>" in
  Alcotest.(check string) "exchange MISX→MOEX" "MOEX" (qp "exchange");
  Alcotest.(check string) "symbol" "SBER" (qp "symbol");
  Alcotest.(check string) "tf H1→3600" "3600" (qp "tf");
  Alcotest.(check string) "format" "Simple" (qp "format");
  Alcotest.(check string) "instrumentGroup from board" "TQBR" (qp "instrumentGroup");
  Alcotest.(check int) "2 bars" 2 (List.length bars);
  let last = List.nth bars 1 in
  Alcotest.(check (float 1e-6)) "last close" 320.5 (Decimal.to_float last.close)

let order_ok_response = {|{ "message": "success", "orderNumber": "777" }|}

let header req name = List.assoc_opt name req.Http_transport.headers

let test_place_market_order () =
  let t, captured = scripted ~data_response:order_ok_response in
  let rest = Rest.make ~transport:t ~cfg:(make_cfg ()) in
  let order_id =
    Rest.place_order rest ~instrument:sber ~side:Side.Buy ~quantity:10 ~kind:Market
      ~tif:DAY ~comment:"42"
  in
  Alcotest.(check string) "orderNumber" "777" order_id;
  let req = !captured in
  Alcotest.(check bool) "POST" true (req.meth = `POST);
  Alcotest.(check string)
    "market endpoint" "/commandapi/warptrans/TRADE/v2/client/orders/actions/market"
    (Uri.path req.url);
  Alcotest.(check bool) "X-REQID present" true (Option.is_some (header req "X-REQID"));
  let body = Yojson.Safe.from_string (Option.get req.body) in
  let open Yojson.Safe.Util in
  Alcotest.(check string) "side" "buy" (body |> member "side" |> to_string);
  Alcotest.(check int) "quantity" 10 (body |> member "quantity" |> to_int);
  Alcotest.(check string)
    "portfolio" "D12345"
    (body |> member "user" |> member "portfolio" |> to_string);
  Alcotest.(check string)
    "instrument exchange" "MOEX"
    (body |> member "instrument" |> member "exchange" |> to_string);
  (* placement_id stamped as the venue-side correlation anchor *)
  Alcotest.(check string)
    "comment carries placement id" "42"
    (body |> member "comment" |> to_string)

let test_place_limit_order_has_price () =
  let t, captured = scripted ~data_response:order_ok_response in
  let rest = Rest.make ~transport:t ~cfg:(make_cfg ()) in
  let _ =
    Rest.place_order rest ~instrument:sber ~side:Side.Sell ~quantity:5
      ~kind:(Limit (Decimal.of_float 300.5))
      ~tif:GTC ~comment:"7"
  in
  let req = !captured in
  Alcotest.(check string)
    "limit endpoint" "/commandapi/warptrans/TRADE/v2/client/orders/actions/limit"
    (Uri.path req.url);
  let body = Yojson.Safe.from_string (Option.get req.body) in
  let price = Yojson.Safe.Util.(body |> member "price") in
  (* Alor expects [price] as a JSON number, not a decimal-as-string. *)
  Alcotest.(check bool)
    "price is a JSON number" true
    (match price with
    | `Float _ | `Int _ -> true
    | _ -> false)

let tests =
  [
    ("history request & decode", `Quick, test_bars_request_and_decode);
    ("place market order", `Quick, test_place_market_order);
    ("place limit order carries price", `Quick, test_place_limit_order_has_price);
  ]
