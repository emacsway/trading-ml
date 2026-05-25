(** Unit tests for [Alor.Ws]: the channel-agnostic frame split (data
    vs control) and the subscribe / unsubscribe request encoders. *)

open Core
open Alor

let cfg = Config.make ~refresh_token:"R" ~portfolio:"D12345" ()

let sber =
  Instrument.make ~ticker:(Ticker.of_string "SBER") ~venue:(Mic.of_string "MISX")
    ~board:(Board.of_string "TQBR") ()

let test_frame_data () =
  match
    Ws.frame_of_json
      (Yojson.Safe.from_string {|{"data":{"time":1,"close":2},"guid":"g1"}|})
  with
  | Some { guid; data } ->
      Alcotest.(check string) "guid" "g1" guid;
      Alcotest.(check bool)
        "data carries time" true
        (Yojson.Safe.Util.member "time" data <> `Null)
  | None -> Alcotest.fail "expected a data frame"

let test_frame_control_is_none () =
  let control = {|{"requestGuid":"g1","httpCode":200,"message":"ok"}|} in
  Alcotest.(check bool)
    "control frame → None" true
    (Ws.frame_of_json (Yojson.Safe.from_string control) = None);
  Alcotest.(check bool)
    "data without guid → None" true
    (Ws.frame_of_json (Yojson.Safe.from_string {|{"data":{"x":1}}|}) = None)

let member j k = Yojson.Safe.Util.member k j

let test_bars_subscribe_envelope () =
  let j =
    Ws.Requests.Bars.subscribe ~cfg ~token:"JWT" ~guid:"g1" ~instrument:sber ~timeframe:H1
      ()
  in
  let str k = Yojson.Safe.Util.to_string (member j k) in
  Alcotest.(check string) "opcode" "BarsGetAndSubscribe" (str "opcode");
  Alcotest.(check string) "code (bare ticker)" "SBER" (str "code");
  Alcotest.(check string) "exchange" "MOEX" (str "exchange");
  Alcotest.(check string) "instrumentGroup" "TQBR" (str "instrumentGroup");
  Alcotest.(check string) "token" "JWT" (str "token");
  Alcotest.(check string) "guid" "g1" (str "guid");
  Alcotest.(check string) "tf is string \"3600\"" "3600" (str "tf")

let test_trades_subscribe_envelope () =
  let j = Ws.Requests.Trades.subscribe ~cfg ~token:"JWT" ~guid:"g2" () in
  let str k = Yojson.Safe.Util.to_string (member j k) in
  Alcotest.(check string) "opcode" "TradesGetAndSubscribeV2" (str "opcode");
  Alcotest.(check string) "exchange default" "MOEX" (str "exchange");
  Alcotest.(check string) "portfolio" "D12345" (str "portfolio");
  Alcotest.(check string) "guid" "g2" (str "guid")

let test_unsubscribe_envelope () =
  let j = Ws.Requests.Unsubscribe.make ~token:"JWT" ~guid:"g3" in
  let str k = Yojson.Safe.Util.to_string (member j k) in
  Alcotest.(check string) "opcode" "unsubscribe" (str "opcode");
  Alcotest.(check string) "guid" "g3" (str "guid")

let tests =
  [
    ("frame: data", `Quick, test_frame_data);
    ("frame: control → None", `Quick, test_frame_control_is_none);
    ("bars subscribe envelope", `Quick, test_bars_subscribe_envelope);
    ("trades subscribe envelope", `Quick, test_trades_subscribe_envelope);
    ("unsubscribe envelope", `Quick, test_unsubscribe_envelope);
  ]
