(** Unit tests for [Alor.Dto] / [Alor.Dto.Wire]: order + trade
    decoding (including the partial-fill status derivation Alor lacks a
    wire token for) and the enum / timeframe codecs. *)

open Core
open Alor

let status_str (s : Broker_domain.Order.status) = Broker_domain.Order.status_to_string s

let order_json status ~qty ~filled =
  Printf.sprintf
    (* legacy [qty] deliberately wrong (999) to prove we read [qtyBatch]. *)
    {|{"id":"42","symbol":"SBER","board":"TQBR","exchange":"MOEX","side":"buy",
       "status":"%s","qtyBatch":%d,"qty":999,"filledQtyBatch":%d,"price":300.5,"type":"limit",
       "timeInForce":"goodtillcancelled","transTime":"2026-05-01T10:00:00Z"}|}
    status qty filled

let test_order_fields () =
  let o =
    Dto.Order.of_json (Yojson.Safe.from_string (order_json "working" ~qty:10 ~filled:4))
  in
  Alcotest.(check string) "order_id" "42" o.order_id;
  Alcotest.(check string)
    "ticker" "SBER"
    (Ticker.to_string (Instrument.ticker o.instrument));
  Alcotest.(check string)
    "venue MISX" "MISX"
    (Mic.to_string (Instrument.venue o.instrument));
  Alcotest.(check bool) "side buy" true (o.side = Side.Buy);
  Alcotest.(check (float 1e-6)) "qty" 10.0 (Decimal.to_float o.quantity);
  Alcotest.(check (float 1e-6)) "filled" 4.0 (Decimal.to_float o.filled);
  Alcotest.(check string) "kind LIMIT" "LIMIT" (Broker_domain.Order.kind_to_string o.kind);
  Alcotest.(check string) "tif GTC" "GTC" (Broker_domain.Order.tif_to_string o.tif)

(* Alor has no "partially filled" status; it is derived from the
   filled/quantity split on a [working] order. *)
let test_status_derivation () =
  let status_of s ~qty ~filled =
    status_str
      (Dto.Order.of_json (Yojson.Safe.from_string (order_json s ~qty ~filled))).status
  in
  Alcotest.(check string) "working+0 → NEW" "NEW" (status_of "working" ~qty:10 ~filled:0);
  Alcotest.(check string)
    "working+partial → PARTIALLY_FILLED" "PARTIALLY_FILLED"
    (status_of "working" ~qty:10 ~filled:4);
  Alcotest.(check string)
    "working+full → FILLED" "FILLED"
    (status_of "working" ~qty:10 ~filled:10);
  Alcotest.(check string)
    "filled → FILLED" "FILLED"
    (status_of "filled" ~qty:10 ~filled:10);
  Alcotest.(check string)
    "canceled → CANCELLED" "CANCELLED"
    (status_of "canceled" ~qty:10 ~filled:0);
  Alcotest.(check string)
    "rejected → REJECTED" "REJECTED"
    (status_of "rejected" ~qty:10 ~filled:0)

(* Simple frame: parent id is [orderno]; quantity is read from the lot
   field [qtyBatch], not [qty] (legacy) or [qtyUnits] (shares) — both
   set to trap values here. *)
let test_trade_rest_orderno () =
  let j =
    {|{"id":"T1","orderno":"42","symbol":"SBER","board":"TQBR","exchange":"MOEX",
       "date":"2026-05-01T10:01:00Z","qtyBatch":4,"qtyUnits":40,"qty":999,
       "price":300.0,"side":"buy","commission":1.5}|}
  in
  let tr = Dto.Trade.of_json (Yojson.Safe.from_string j) in
  Alcotest.(check string) "parent order_id (orderno)" "42" tr.order_id;
  Alcotest.(check string) "trade_id" "T1" tr.trade.trade_id;
  Alcotest.(check (float 1e-6))
    "qtyBatch (lots), not qty/qtyUnits" 4.0
    (Decimal.to_float tr.trade.quantity);
  Alcotest.(check (float 1e-6)) "price" 300.0 (Decimal.to_float tr.trade.price);
  Alcotest.(check (float 1e-6)) "fee" 1.5 (Decimal.to_float tr.trade.fee)

(* The [orderNo] casing (V2/Heavy) is accepted as a fallback; null
   commission (derivatives) decodes to a zero fee. *)
let test_trade_ws_orderno_and_null_fee () =
  let j =
    {|{"id":"T2","orderNo":"999","symbol":"SBER","exchange":"MOEX",
       "date":"2026-05-01T10:02:00Z","qtyBatch":1,"price":301.0,"side":"sell","commission":null}|}
  in
  let tr = Dto.Trade.of_json (Yojson.Safe.from_string j) in
  Alcotest.(check string) "parent order_id (orderNo fallback)" "999" tr.order_id;
  Alcotest.(check bool) "side sell" true (tr.side = Side.Sell);
  Alcotest.(check (float 1e-6))
    "null commission → 0 fee" 0.0
    (Decimal.to_float tr.trade.fee)

let test_wire_enums () =
  Alcotest.(check string) "side buy" "buy" (Dto.Wire.side_to_wire Side.Buy);
  Alcotest.(check string) "side sell" "sell" (Dto.Wire.side_to_wire Side.Sell);
  Alcotest.(check string) "tif GTC" "goodtillcancelled" (Dto.Wire.tif_to_wire GTC);
  Alcotest.(check string) "tif DAY" "oneday" (Dto.Wire.tif_to_wire DAY);
  Alcotest.(check string) "kind market" "market" (Dto.Wire.kind_to_path Market);
  Alcotest.(check string)
    "kind limit" "limit"
    (Dto.Wire.kind_to_path (Limit (Decimal.of_int 1)))

let test_timeframe_encoding () =
  Alcotest.(check string) "M1 → 60" "60" (Dto.Wire.timeframe_query M1);
  Alcotest.(check string) "H1 → 3600" "3600" (Dto.Wire.timeframe_query H1);
  Alcotest.(check string) "D1 → D" "D" (Dto.Wire.timeframe_query D1);
  Alcotest.(check string) "MN1 → M" "M" (Dto.Wire.timeframe_query MN1);
  Alcotest.(check string) "M5 → 300" "300" (Dto.Wire.timeframe_query M5);
  Alcotest.(check string) "W1 → W" "W" (Dto.Wire.timeframe_query W1)

let tests =
  [
    ("order fields", `Quick, test_order_fields);
    ("status derivation", `Quick, test_status_derivation);
    ("trade REST orderno", `Quick, test_trade_rest_orderno);
    ("trade WS orderNo + null fee", `Quick, test_trade_ws_orderno_and_null_fee);
    ("wire enums", `Quick, test_wire_enums);
    ("timeframe encoding", `Quick, test_timeframe_encoding);
  ]
