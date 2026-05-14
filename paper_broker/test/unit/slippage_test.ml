(** Unit tests for {!Paper_broker.Slippage}. *)

module Slippage_bps = Paper_broker.Slippage.Values.Slippage_bps
module Slippage = Paper_broker.Slippage

let dec = Decimal.of_string

let test_negative_bps_rejected () =
  match Slippage_bps.of_decimal (dec "-1") with
  | exception Invalid_argument _ -> ()
  | _ -> Alcotest.fail "expected Invalid_argument for negative bps"

let test_zero_bps_is_identity () =
  let bps = Slippage_bps.zero in
  let p = dec "100" in
  Alcotest.(check bool)
    "Buy unchanged" true
    (Decimal.equal (Slippage.apply ~bps Core.Side.Buy p) p);
  Alcotest.(check bool)
    "Sell unchanged" true
    (Decimal.equal (Slippage.apply ~bps Core.Side.Sell p) p)

let test_buy_pays_up () =
  let bps = Slippage_bps.of_decimal (dec "5") in
  let price = dec "100" in
  let r = Slippage.apply ~bps Core.Side.Buy price in
  Alcotest.(check string) "100 + 5 bps = 100.05" "100.05" (Decimal.to_string r)

let test_sell_receives_less () =
  let bps = Slippage_bps.of_decimal (dec "5") in
  let price = dec "100" in
  let r = Slippage.apply ~bps Core.Side.Sell price in
  Alcotest.(check string) "100 - 5 bps = 99.95" "99.95" (Decimal.to_string r)

let tests =
  [
    ("negative bps rejected", `Quick, test_negative_bps_rejected);
    ("zero bps is identity", `Quick, test_zero_bps_is_identity);
    ("buy pays up", `Quick, test_buy_pays_up);
    ("sell receives less", `Quick, test_sell_receives_less);
  ]
