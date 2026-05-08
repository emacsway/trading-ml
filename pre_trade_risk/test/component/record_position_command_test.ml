(** BDD specification for absorbing an upstream position change into
    a per-book Risk_view.

    Covers the upsert of a new position, the replacement of an
    existing one, and zero-quantity pruning. *)

module Gherkin = Gherkin_edsl
open Test_harness

let dec_eq label expected actual =
  Alcotest.(check bool)
    (Printf.sprintf "%s: %s = %s" label (Decimal.to_string expected)
       (Decimal.to_string actual))
    true
    (Decimal.equal expected actual)

let new_position_upserts =
  Gherkin.scenario "A new position for an unseen instrument is recorded as is" fresh_ctx
    [
      Gherkin.given "an empty book \"alpha\"" (fun ctx ->
          ctx |> seed_book ~book_id:"alpha");
      Gherkin.when_ "a position change of +10 SBER@MISX (avg 100) is recorded" (fun ctx ->
          ctx
          |> record_position ~book_id:"alpha" ~symbol:"SBER@MISX" ~delta_qty:"10"
               ~new_qty:"10" ~avg_price:"100");
      Gherkin.then_ "the workflow completes without error" (fun ctx ->
          match ctx.last_record_position_result with
          | Some (Ok ()) -> ()
          | _ -> Alcotest.fail "expected workflow success");
      Gherkin.then_ "the book's view holds 10 SBER@MISX" (fun ctx ->
          let r =
            risk_view_ref_for ctx (Pre_trade_risk.Common.Book_id.of_string "alpha")
          in
          let inst = Core.Instrument.of_qualified "SBER@MISX" in
          dec_eq "position quantity" (Decimal.of_int 10)
            (Pre_trade_risk.Risk_view.position !r inst));
    ]

let zero_qty_prunes =
  Gherkin.scenario "Recording a zero quantity prunes the position from the view" fresh_ctx
    [
      Gherkin.given "a book \"alpha\" already holding 10 SBER@MISX" (fun ctx ->
          ctx
          |> with_position ~book_id:"alpha" ~symbol:"SBER@MISX" ~qty:"10" ~avg_price:"100");
      Gherkin.when_ "a position change driving the quantity to zero is recorded"
        (fun ctx ->
          ctx
          |> record_position ~book_id:"alpha" ~symbol:"SBER@MISX" ~delta_qty:"-10"
               ~new_qty:"0" ~avg_price:"100");
      Gherkin.then_ "the position is removed from the view" (fun ctx ->
          let r =
            risk_view_ref_for ctx (Pre_trade_risk.Common.Book_id.of_string "alpha")
          in
          let inst = Core.Instrument.of_qualified "SBER@MISX" in
          dec_eq "position quantity" Decimal.zero
            (Pre_trade_risk.Risk_view.position !r inst);
          Alcotest.(check int)
            "positions list is empty" 0
            (List.length (Pre_trade_risk.Risk_view.positions !r)));
    ]

let replace_existing_position =
  Gherkin.scenario
    "A subsequent change for an already-known instrument replaces, not duplicates"
    fresh_ctx
    [
      Gherkin.given "a book \"alpha\" already holding 10 SBER@MISX" (fun ctx ->
          ctx
          |> with_position ~book_id:"alpha" ~symbol:"SBER@MISX" ~qty:"10" ~avg_price:"100");
      Gherkin.when_ "a position change to 25 SBER@MISX is recorded" (fun ctx ->
          ctx
          |> record_position ~book_id:"alpha" ~symbol:"SBER@MISX" ~delta_qty:"15"
               ~new_qty:"25" ~avg_price:"110");
      Gherkin.then_ "the view holds exactly one entry for SBER@MISX, with the new qty"
        (fun ctx ->
          let r =
            risk_view_ref_for ctx (Pre_trade_risk.Common.Book_id.of_string "alpha")
          in
          let inst = Core.Instrument.of_qualified "SBER@MISX" in
          dec_eq "position quantity" (Decimal.of_int 25)
            (Pre_trade_risk.Risk_view.position !r inst);
          Alcotest.(check int)
            "positions list size" 1
            (List.length (Pre_trade_risk.Risk_view.positions !r)));
    ]

let feature =
  Gherkin.feature "Record position command"
    [ new_position_upserts; zero_qty_prunes; replace_existing_position ]
