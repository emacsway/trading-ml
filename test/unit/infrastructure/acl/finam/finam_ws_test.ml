(** Wire-format tests for [Finam.Ws]: subscription envelope encoding
    and inbound event decoding. Mirrors the asyncapi-v1.0.0 spec
    bundled in [finam-trade-api/specs/asyncapi/]. *)

open Core

let mk_inst ?board ticker mic =
  Instrument.make
    ~ticker:(Ticker.of_string ticker)
    ~venue:(Mic.of_string mic)
    ?board:(Option.map Board.of_string board)
    ()

let test_subscribe_bars_envelope () =
  let inst = mk_inst "SBER" "MISX" in
  let j = Finam.Ws.subscribe_message ~token:"JWT123"
    (Sub_bars { instrument = inst; timeframe = Timeframe.D1 }) in
  let open Yojson.Safe.Util in
  Alcotest.(check string) "action"
    "SUBSCRIBE" (member "action" j |> to_string);
  Alcotest.(check string) "type"
    "BARS" (member "type" j |> to_string);
  Alcotest.(check string) "token in body"
    "JWT123" (member "token" j |> to_string);
  let data = member "data" j in
  Alcotest.(check string) "data.symbol"
    "SBER@MISX" (member "symbol" data |> to_string);
  Alcotest.(check string) "data.timeframe"
    "TIME_FRAME_D" (member "timeframe" data |> to_string)

let test_unsubscribe_bars_envelope () =
  let inst = mk_inst "SBER" "MISX" in
  let j = Finam.Ws.unsubscribe_message ~token:"T"
    (Sub_bars { instrument = inst; timeframe = Timeframe.H1 }) in
  let open Yojson.Safe.Util in
  Alcotest.(check string) "action"
    "UNSUBSCRIBE" (member "action" j |> to_string);
  Alcotest.(check string) "type"
    "BARS" (member "type" j |> to_string)

let test_subscribe_quotes_envelope () =
  let a = mk_inst "SBER" "MISX" in
  let b = mk_inst "GAZP" "MISX" in
  let j = Finam.Ws.subscribe_message ~token:"T"
    (Sub_quotes [a; b]) in
  let open Yojson.Safe.Util in
  Alcotest.(check string) "type"
    "QUOTES" (member "type" j |> to_string);
  let symbols =
    member "data" j |> member "symbols" |> to_list
    |> List.map to_string
  in
  Alcotest.(check (list string)) "symbols list"
    ["SBER@MISX"; "GAZP@MISX"] symbols

let test_subscribe_account_envelope () =
  let j = Finam.Ws.subscribe_message ~token:"T"
    (Sub_account "ACC1") in
  let open Yojson.Safe.Util in
  Alcotest.(check string) "type"
    "ACCOUNT" (member "type" j |> to_string);
  Alcotest.(check string) "data.account_id"
    "ACC1" (member "data" j |> member "account_id" |> to_string)

(** Sample DATA envelope with a BARS payload, mirroring the asyncapi
    [SubscribeBarsResponse] shape. *)
let bars_data_payload = {|
  { "type": "DATA",
    "subscription_type": "BARS",
    "subscription_key": "k1",
    "timestamp": 1700000000,
    "payload": {
      "symbol": "SBER@MISX",
      "bars": [
        { "timestamp": "2026-04-16T10:00:00Z",
          "open": "300.0", "high": "301.5",
          "low": "299.8", "close": "301.0",
          "volume": "12345" }
      ]
    } }
|}

let test_decode_bars_data () =
  let j = Yojson.Safe.from_string bars_data_payload in
  match Finam.Ws.event_of_json j with
  | Bars { instrument; bars } ->
    Alcotest.(check string) "ticker round-trips"
      "SBER" (Ticker.to_string (Instrument.ticker instrument));
    Alcotest.(check string) "venue round-trips"
      "MISX" (Mic.to_string (Instrument.venue instrument));
    Alcotest.(check int) "1 bar" 1 (List.length bars);
    let c = List.hd bars in
    Alcotest.(check (float 1e-6)) "close" 301.0
      (Decimal.to_float c.Candle.close)
  | _ -> Alcotest.fail "expected Bars event"

let test_decode_error () =
  let j = Yojson.Safe.from_string {|
    { "type": "ERROR",
      "subscription_type": "BARS",
      "timestamp": 1700000000,
      "error_info": {
        "code": 401,
        "type": "UNAUTHENTICATED",
        "message": "JWT expired"
      } }
  |} in
  match Finam.Ws.event_of_json j with
  | Error_ev { code; type_; message } ->
    Alcotest.(check int) "code" 401 code;
    Alcotest.(check string) "type" "UNAUTHENTICATED" type_;
    Alcotest.(check string) "message" "JWT expired" message
  | _ -> Alcotest.fail "expected Error_ev"

let test_decode_lifecycle () =
  let j = Yojson.Safe.from_string {|
    { "type": "EVENT",
      "timestamp": 1700000000,
      "event_info": {
        "event": "HANDSHAKE_SUCCESS",
        "code": 0,
        "reason": "ok"
      } }
  |} in
  match Finam.Ws.event_of_json j with
  | Lifecycle { event; code; reason } ->
    Alcotest.(check string) "event" "HANDSHAKE_SUCCESS" event;
    Alcotest.(check int) "code" 0 code;
    Alcotest.(check string) "reason" "ok" reason
  | _ -> Alcotest.fail "expected Lifecycle"

let tests = [
  "subscribe BARS envelope",      `Quick, test_subscribe_bars_envelope;
  "unsubscribe BARS envelope",    `Quick, test_unsubscribe_bars_envelope;
  "subscribe QUOTES envelope",    `Quick, test_subscribe_quotes_envelope;
  "subscribe ACCOUNT envelope",   `Quick, test_subscribe_account_envelope;
  "decode BARS data event",       `Quick, test_decode_bars_data;
  "decode ERROR event",           `Quick, test_decode_error;
  "decode EVENT lifecycle",       `Quick, test_decode_lifecycle;
]
