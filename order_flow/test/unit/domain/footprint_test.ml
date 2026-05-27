open Core
module Footprint = Order_flow.Footprint
module Print = Order_flow.Footprint.Values.Print
module Aggressor = Order_flow.Footprint.Values.Aggressor
module Cluster = Order_flow.Footprint.Values.Cluster
module Bar_boundary = Order_flow.Footprint.Values.Bar_boundary
module Bar_opened = Order_flow.Footprint.Events.Bar_opened
module FC = Order_flow.Footprint.Events.Footprint_completed

let d = Decimal.of_float

let dec =
  Alcotest.testable
    (fun fmt x -> Format.fprintf fmt "%s" (Decimal.to_string x))
    Decimal.equal

let inst =
  Instrument.make ~ticker:(Ticker.of_string "SBER") ~venue:(Mic.of_string "MISX") ()

(* M5 = 300s buckets. *)
let boundary = Bar_boundary.Time Timeframe.M5

let pr ?(ts = 0L) ~price ~size aggressor =
  Print.make ~price:(d price) ~size:(d size) ~ts ~aggressor

(* Build a bar from a non-empty print list: open on the head, absorb
   the tail. Callers keep every [ts] in one bucket so the [absorb]
   precondition (classify = In_bar) holds. *)
let build prints =
  match prints with
  | [] -> invalid_arg "build: empty"
  | first :: rest ->
      let bar, _ = Footprint.open_ ~instrument:inst ~boundary ~first in
      List.fold_left Footprint.absorb bar rest

let test_open_seeds () =
  let first = pr ~ts:10L ~price:100.0 ~size:5.0 Aggressor.Buy in
  let bar, ev = Footprint.open_ ~instrument:inst ~boundary ~first in
  Alcotest.(check bool) "forming" true (bar.Footprint.status = Footprint.Forming);
  Alcotest.(check int64) "open_ts floored to bucket" 0L bar.Footprint.open_ts;
  Alcotest.check dec "open_price = first price" (d 100.0) bar.Footprint.open_price;
  Alcotest.check dec "volume = first size" (d 5.0) bar.Footprint.volume;
  Alcotest.(check int64) "event carries open_ts" 0L ev.Bar_opened.open_ts

let test_absorb_volume_and_delta () =
  let bar =
    build
      [
        pr ~price:100.0 ~size:5.0 Aggressor.Buy;
        pr ~price:101.0 ~size:3.0 Aggressor.Sell;
        pr ~price:100.0 ~size:2.0 Aggressor.Indeterminate;
        pr ~price:99.0 ~size:4.0 Aggressor.Buy;
      ]
  in
  Alcotest.check dec "volume = 5+3+2+4" (d 14.0) bar.Footprint.volume;
  Alcotest.check dec "delta = +5 -3 +0 +4" (d 6.0) bar.Footprint.delta

let test_indeterminate_excluded_from_delta () =
  let bar = build [ pr ~price:100.0 ~size:10.0 Aggressor.Indeterminate ] in
  Alcotest.check dec "auction volume counts" (d 10.0) bar.Footprint.volume;
  Alcotest.check dec "auction volume leaves delta at 0" (d 0.0) bar.Footprint.delta

let test_classify () =
  (* open in the second bucket: open_ts = 300 *)
  let first = pr ~ts:400L ~price:100.0 ~size:1.0 Aggressor.Buy in
  let bar, _ = Footprint.open_ ~instrument:inst ~boundary ~first in
  let at ts = Footprint.classify bar (pr ~ts ~price:100.0 ~size:1.0 Aggressor.Buy) in
  Alcotest.(check bool) "same bucket -> In_bar" true (at 350L = Footprint.In_bar);
  Alcotest.(check bool)
    "later bucket -> Opens_later" true
    (at 700L = Footprint.Opens_later);
  Alcotest.(check bool) "earlier bucket -> Late" true (at 100L = Footprint.Late)

let test_seal () =
  let bar =
    build
      [
        pr ~price:100.0 ~size:5.0 Aggressor.Buy;
        pr ~price:101.0 ~size:3.0 Aggressor.Sell;
        pr ~price:100.0 ~size:2.0 Aggressor.Indeterminate;
        pr ~price:99.0 ~size:4.0 Aggressor.Buy;
      ]
  in
  let sealed, ev = Footprint.seal bar in
  Alcotest.(check bool) "sealed" true (sealed.Footprint.status = Footprint.Sealed);
  Alcotest.check dec "volume" (d 14.0) ev.FC.volume;
  Alcotest.check dec "delta" (d 6.0) ev.FC.delta;
  Alcotest.check dec "open" (d 100.0) ev.FC.open_price;
  Alcotest.check dec "high" (d 101.0) ev.FC.high;
  Alcotest.check dec "low" (d 99.0) ev.FC.low;
  Alcotest.check dec "close = last print" (d 99.0) ev.FC.close;
  (* price 100 totals 7 (buy 5 + auction 2), beating 101->3 and 99->4 *)
  Alcotest.check dec "POC = max-volume price" (d 100.0) ev.FC.poc_price

let test_poc_tie_lowest_price () =
  let bar =
    build
      [ pr ~price:100.0 ~size:5.0 Aggressor.Buy; pr ~price:99.0 ~size:5.0 Aggressor.Buy ]
  in
  let _, ev = Footprint.seal bar in
  Alcotest.check dec "tie resolves to lowest price" (d 99.0) ev.FC.poc_price

let test_fold_order_independence () =
  let prints =
    [
      pr ~price:100.0 ~size:5.0 Aggressor.Buy;
      pr ~price:101.0 ~size:3.0 Aggressor.Sell;
      pr ~price:100.0 ~size:2.0 Aggressor.Indeterminate;
      pr ~price:99.0 ~size:4.0 Aggressor.Buy;
    ]
  in
  let reordered =
    [
      pr ~price:99.0 ~size:4.0 Aggressor.Buy;
      pr ~price:100.0 ~size:2.0 Aggressor.Indeterminate;
      pr ~price:101.0 ~size:3.0 Aggressor.Sell;
      pr ~price:100.0 ~size:5.0 Aggressor.Buy;
    ]
  in
  let _, a = Footprint.seal (build prints) in
  let _, b = Footprint.seal (build reordered) in
  (* The footprint is order-independent: volume, delta, POC, high, low
     coincide. open/close are NOT — they are the first/last print by
     definition — so they are deliberately not asserted equal here. *)
  Alcotest.check dec "volume" a.FC.volume b.FC.volume;
  Alcotest.check dec "delta" a.FC.delta b.FC.delta;
  Alcotest.check dec "POC" a.FC.poc_price b.FC.poc_price;
  Alcotest.check dec "high" a.FC.high b.FC.high;
  Alcotest.check dec "low" a.FC.low b.FC.low

(* Property mirror of the proved conservation law: whatever the prints,
   the sealed bar's volume equals the sum of their sizes. *)
let prop_conservation =
  QCheck.Test.make ~count:300 ~name:"volume conservation"
    QCheck.(
      list
        (pair (int_range 1 1000)
           (map
              (fun i ->
                match i mod 3 with
                | 0 -> Aggressor.Buy
                | 1 -> Aggressor.Sell
                | _ -> Aggressor.Indeterminate)
              (int_range 0 2))))
    (fun pairs ->
      match pairs with
      | [] -> true
      | (s0, a0) :: rest ->
          let mk (s, a) = pr ~price:100.0 ~size:(float_of_int s) a in
          let bar, _ = Footprint.open_ ~instrument:inst ~boundary ~first:(mk (s0, a0)) in
          let bar = List.fold_left (fun b p -> Footprint.absorb b (mk p)) bar rest in
          let expected = List.fold_left (fun acc (s, _) -> acc + s) s0 rest in
          Decimal.equal bar.Footprint.volume (d (float_of_int expected)))

let test_conservation_qcheck () = QCheck.Test.check_exn prop_conservation

let tests =
  [
    Alcotest.test_case "open seeds a forming bar" `Quick test_open_seeds;
    Alcotest.test_case "absorb accumulates volume and delta" `Quick
      test_absorb_volume_and_delta;
    Alcotest.test_case "indeterminate volume excluded from delta" `Quick
      test_indeterminate_excluded_from_delta;
    Alcotest.test_case "classify in/later/late" `Quick test_classify;
    Alcotest.test_case "seal emits the completed footprint" `Quick test_seal;
    Alcotest.test_case "POC tie resolves to lowest price" `Quick test_poc_tie_lowest_price;
    Alcotest.test_case "fold-order independence of the footprint" `Quick
      test_fold_order_independence;
    Alcotest.test_case "conservation (property)" `Quick test_conservation_qcheck;
  ]
