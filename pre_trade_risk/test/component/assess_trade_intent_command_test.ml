(** BDD specification for assessing a trade intent against the
    pre-trade hard gate.

    Covers the approve path (announces an Approval IE carrying the
    requested quantity), the three rejection paths (cash buffer / gross
    exposure / leverage — all announce a Rejection IE with a
    human-readable reason), unknown-book lookup, and validation
    failures (announce nothing). *)

module Gherkin = Gherkin_edsl
open Test_harness

let contains_substring ~needle haystack =
  let nl = String.length needle in
  let hl = String.length haystack in
  let rec loop i =
    if i + nl > hl then false
    else if String.sub haystack i nl = needle then true
    else loop (i + 1)
  in
  loop 0

let approve_within_limits =
  Gherkin.scenario
    "An intent within all hard limits is approved at the requested quantity" fresh_ctx
    [
      Gherkin.given "a book \"alpha\" with 10 000 cash and no positions" (fun ctx ->
          ctx |> with_cash ~book_id:"alpha" ~cash:"10000");
      Gherkin.when_ "a buy of 10 SBER@MISX at 150 is assessed" (fun ctx ->
          ctx
          |> assess ~book_id:"alpha" ~side:"BUY" ~symbol:"SBER@MISX" ~quantity:"10"
               ~price:"150");
      Gherkin.then_ "the assessment completes without error" (fun ctx ->
          match ctx.last_assess_result with
          | Some (Ok ()) -> ()
          | _ -> Alcotest.fail "expected workflow success");
      Gherkin.then_
        "an approval is announced with the original side, instrument and quantity"
        (fun ctx ->
          match !(ctx.approved_pub) with
          | [ ie ] ->
              Alcotest.(check string) "book_id" "alpha" ie.book_id;
              Alcotest.(check string) "side" "BUY" ie.side;
              Alcotest.(check string) "symbol" "SBER@MISX" ie.symbol;
              Alcotest.(check string) "quantity" "10" ie.quantity
          | other ->
              Alcotest.fail
                (Printf.sprintf "expected one approval announcement, got %d"
                   (List.length other)));
      Gherkin.then_ "no rejection is announced" (fun ctx ->
          Alcotest.(check int) "rejected count" 0 (List.length !(ctx.rejected_pub)));
    ]

let reject_for_cash_buffer =
  Gherkin.scenario
    "An intent that would breach the minimum-cash floor is refused with a cash reason"
    fresh_ctx
    [
      Gherkin.given "limits with a 500 minimum-cash buffer" (fun ctx ->
          ctx
          |> with_limits
               ~limits:
                 (Pre_trade_risk.Risk_limits.make ~min_cash_buffer:(Decimal.of_int 500)
                    ~max_gross_exposure:(Decimal.of_int 1_000_000) ~max_leverage:5.0));
      Gherkin.given "a book \"alpha\" with only 1 000 cash" (fun ctx ->
          ctx |> with_cash ~book_id:"alpha" ~cash:"1000");
      Gherkin.when_ "a buy of 10 SBER@MISX at 100 is assessed" (fun ctx ->
          ctx
          |> assess ~book_id:"alpha" ~side:"BUY" ~symbol:"SBER@MISX" ~quantity:"10"
               ~price:"100");
      Gherkin.then_ "the assessment completes without error" (fun ctx ->
          match ctx.last_assess_result with
          | Some (Ok ()) -> ()
          | _ -> Alcotest.fail "expected workflow success");
      Gherkin.then_ "no approval is announced" (fun ctx ->
          Alcotest.(check int) "approved count" 0 (List.length !(ctx.approved_pub)));
      Gherkin.then_
        "a rejection is announced carrying the original attempt and a cash-buffer reason"
        (fun ctx ->
          match !(ctx.rejected_pub) with
          | [ ie ] ->
              Alcotest.(check string) "book_id" "alpha" ie.book_id;
              Alcotest.(check string) "side" "BUY" ie.side;
              Alcotest.(check string) "symbol" "SBER@MISX" ie.symbol;
              Alcotest.(check string) "quantity" "10" ie.quantity;
              Alcotest.(check bool)
                (Printf.sprintf "reason mentions min_cash_buffer (got %S)" ie.reason)
                true
                (contains_substring ~needle:"min_cash_buffer" ie.reason)
          | other ->
              Alcotest.fail
                (Printf.sprintf "expected one rejection announcement, got %d"
                   (List.length other)));
    ]

let reject_for_max_gross_exposure =
  Gherkin.scenario
    "An intent that would push gross exposure past the cap is refused with a gross reason"
    fresh_ctx
    [
      Gherkin.given "limits with a 1 500 max gross exposure and no leverage cap"
        (fun ctx ->
          ctx
          |> with_limits
               ~limits:
                 (Pre_trade_risk.Risk_limits.make ~min_cash_buffer:Decimal.zero
                    ~max_gross_exposure:(Decimal.of_int 1_500) ~max_leverage:50.0));
      Gherkin.given "a book \"alpha\" with 10 000 cash and 10 SBER@MISX at 100"
        (fun ctx ->
          ctx
          |> with_cash ~book_id:"alpha" ~cash:"10000"
          |> with_position ~book_id:"alpha" ~symbol:"SBER@MISX" ~qty:"10" ~avg_price:"100");
      Gherkin.when_ "a buy of 10 more SBER@MISX at 100 is assessed" (fun ctx ->
          ctx
          |> assess ~book_id:"alpha" ~side:"BUY" ~symbol:"SBER@MISX" ~quantity:"10"
               ~price:"100");
      Gherkin.then_ "a rejection is announced and the reason mentions max_gross_exposure"
        (fun ctx ->
          match !(ctx.rejected_pub) with
          | [ ie ] ->
              Alcotest.(check bool)
                (Printf.sprintf "reason mentions max_gross_exposure (got %S)" ie.reason)
                true
                (contains_substring ~needle:"max_gross_exposure" ie.reason)
          | _ -> Alcotest.fail "expected one rejection announcement");
    ]

let reject_for_max_leverage =
  Gherkin.scenario
    "An intent that would push gross/equity past the leverage cap is refused with a \
     leverage reason"
    fresh_ctx
    [
      Gherkin.given "limits with a 1.5x leverage cap and no other ceilings" (fun ctx ->
          ctx
          |> with_limits
               ~limits:
                 (Pre_trade_risk.Risk_limits.make ~min_cash_buffer:Decimal.zero
                    ~max_gross_exposure:(Decimal.of_int 1_000_000) ~max_leverage:1.5));
      Gherkin.given "a book \"alpha\" with 1 000 cash and no positions" (fun ctx ->
          ctx |> with_cash ~book_id:"alpha" ~cash:"1000");
      Gherkin.when_ "a sell of 20 SBER@MISX at 100 is assessed" (fun ctx ->
          (* SELL adds notional to cash (no buffer breach), no existing positions
             keeps gross_after = 2000 below the 1M cap, equity = 1000, leverage =
             2.0 > 1.5 *)
          ctx
          |> assess ~book_id:"alpha" ~side:"SELL" ~symbol:"SBER@MISX" ~quantity:"20"
               ~price:"100");
      Gherkin.then_ "a rejection is announced and the reason mentions max_leverage"
        (fun ctx ->
          match !(ctx.rejected_pub) with
          | [ ie ] ->
              Alcotest.(check bool)
                (Printf.sprintf "reason mentions max_leverage (got %S)" ie.reason)
                true
                (contains_substring ~needle:"max_leverage" ie.reason)
          | _ -> Alcotest.fail "expected one rejection announcement");
    ]

let unknown_book_announces_nothing =
  Gherkin.scenario "An intent for a book the gate has never seen announces nothing"
    fresh_ctx
    [
      Gherkin.given "no books are seeded" (fun ctx -> ctx);
      Gherkin.when_ "an intent for the unknown book \"ghost\" is assessed" (fun ctx ->
          ctx
          |> assess ~book_id:"ghost" ~side:"BUY" ~symbol:"SBER@MISX" ~quantity:"1"
               ~price:"100");
      Gherkin.then_ "the workflow surfaces an Unknown_book error" (fun ctx ->
          match ctx.last_assess_result with
          | Some (Error errs) ->
              Alcotest.(check bool)
                "Unknown_book is in the error tail" true
                (List.exists
                   (function
                     | Assess_h.Unknown_book _ -> true
                     | _ -> false)
                   errs)
          | _ -> Alcotest.fail "expected workflow error");
      Gherkin.then_ "neither an approval nor a rejection is announced" (fun ctx ->
          Alcotest.(check int) "approved count" 0 (List.length !(ctx.approved_pub));
          Alcotest.(check int) "rejected count" 0 (List.length !(ctx.rejected_pub)));
    ]

let validation_errors_announce_nothing =
  Gherkin.scenario "Validation failures bypass the gate without announcing anything"
    fresh_ctx
    [
      Gherkin.given "a book \"alpha\" with 1 000 cash" (fun ctx ->
          ctx |> with_cash ~book_id:"alpha" ~cash:"1000");
      Gherkin.when_ "an intent with several malformed fields is assessed" (fun ctx ->
          ctx
          |> assess ~book_id:"alpha" ~side:"NOPE" ~symbol:"SBER@MISX" ~quantity:"0"
               ~price:"100");
      Gherkin.then_ "every malformed field is reported in a single response" (fun ctx ->
          match ctx.last_assess_result with
          | Some (Error errs) ->
              let has_invalid_side =
                List.exists
                  (function
                    | Assess_h.Validation (Assess_h.Invalid_side "NOPE") -> true
                    | _ -> false)
                  errs
              in
              let has_non_positive_qty =
                List.exists
                  (function
                    | Assess_h.Validation (Assess_h.Non_positive_quantity "0") -> true
                    | _ -> false)
                  errs
              in
              Alcotest.(check bool) "Invalid_side present" true has_invalid_side;
              Alcotest.(check bool)
                "Non_positive_quantity present" true has_non_positive_qty
          | _ -> Alcotest.fail "expected workflow error");
      Gherkin.then_ "neither an approval nor a rejection is announced" (fun ctx ->
          Alcotest.(check int) "approved count" 0 (List.length !(ctx.approved_pub));
          Alcotest.(check int) "rejected count" 0 (List.length !(ctx.rejected_pub)));
    ]

let feature =
  Gherkin.feature "Assess trade intent command"
    [
      approve_within_limits;
      reject_for_cash_buffer;
      reject_for_max_gross_exposure;
      reject_for_max_leverage;
      unknown_book_announces_nothing;
      validation_errors_announce_nothing;
    ]
