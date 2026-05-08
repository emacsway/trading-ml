(** Unit tests for {!Portfolio_management.Sizing}. *)

let d = Decimal.of_string

let test_zero_price_is_zero () =
  Alcotest.(check string)
    "zero qty" "0"
    (Decimal.to_string
       (Portfolio_management.Sizing.from_strength ~equity:(d "1000") ~price:Decimal.zero
          ~max_per_instrument_notional:(d "200") ~strength:0.5))

let test_zero_strength_is_zero () =
  Alcotest.(check string)
    "zero qty" "0"
    (Decimal.to_string
       (Portfolio_management.Sizing.from_strength ~equity:(d "1000") ~price:(d "100")
          ~max_per_instrument_notional:(d "200") ~strength:0.0))

let test_unit_strength_uses_full_budget_capped () =
  (* equity 1000 × strength 1.0 = 1000; cap at 200; / price 100 = 2 *)
  Alcotest.(check string)
    "qty" "2"
    (Decimal.to_string
       (Portfolio_management.Sizing.from_strength ~equity:(d "1000") ~price:(d "100")
          ~max_per_instrument_notional:(d "200") ~strength:1.0))

let test_partial_strength_scales () =
  (* equity 1000 × 0.5 = 500; cap 1000; / price 100 = 5 *)
  Alcotest.(check string)
    "qty" "5"
    (Decimal.to_string
       (Portfolio_management.Sizing.from_strength ~equity:(d "1000") ~price:(d "100")
          ~max_per_instrument_notional:(d "1000") ~strength:0.5))

let test_strength_above_one_is_clamped () =
  Alcotest.(check string)
    "qty same as 1.0" "5"
    (Decimal.to_string
       (Portfolio_management.Sizing.from_strength ~equity:(d "1000") ~price:(d "200")
          ~max_per_instrument_notional:(d "5000") ~strength:5.0))

let test_negative_strength_is_clamped_to_zero () =
  Alcotest.(check string)
    "qty zero" "0"
    (Decimal.to_string
       (Portfolio_management.Sizing.from_strength ~equity:(d "1000") ~price:(d "100")
          ~max_per_instrument_notional:(d "200") ~strength:(-0.3)))

let tests =
  [
    Alcotest.test_case "zero price → zero qty" `Quick test_zero_price_is_zero;
    Alcotest.test_case "zero strength → zero qty" `Quick test_zero_strength_is_zero;
    Alcotest.test_case "strength = 1.0 uses budget capped at notional" `Quick
      test_unit_strength_uses_full_budget_capped;
    Alcotest.test_case "partial strength scales linearly" `Quick
      test_partial_strength_scales;
    Alcotest.test_case "strength > 1 clamped to 1" `Quick
      test_strength_above_one_is_clamped;
    Alcotest.test_case "negative strength clamped to 0" `Quick
      test_negative_strength_is_clamped_to_zero;
  ]
