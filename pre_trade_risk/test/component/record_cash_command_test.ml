(** BDD specification for absorbing an upstream cash change into a
    per-book Risk_view. The upstream is authoritative on the new
    balance — [delta] is recorded for audit, not used to derive the
    new value. *)

module Gherkin = Gherkin_edsl
open Test_harness

let dec_eq label expected actual =
  Alcotest.(check bool)
    (Printf.sprintf "%s: %s = %s" label (Decimal.to_string expected)
       (Decimal.to_string actual))
    true
    (Decimal.equal expected actual)

let cash_balance_replaced =
  Gherkin.scenario "An upstream cash event replaces the view's balance with new_balance"
    fresh_ctx
    [
      Gherkin.given "an empty book \"alpha\"" (fun ctx ->
          ctx |> seed_book ~book_id:"alpha");
      Gherkin.when_ "a cash event with delta +1 000 and new_balance 1 000 is recorded"
        (fun ctx -> ctx |> record_cash ~book_id:"alpha" ~delta:"1000" ~new_balance:"1000");
      Gherkin.then_ "the view's cash equals the upstream new_balance" (fun ctx ->
          let r =
            risk_view_ref_for ctx (Pre_trade_risk.Common.Book_id.of_string "alpha")
          in
          dec_eq "cash" (Decimal.of_int 1_000) (Pre_trade_risk.Risk_view.cash !r));
    ]

let cash_balance_overwrites_delta_disagreement =
  Gherkin.scenario
    "When delta and new_balance disagree, the upstream's new_balance still wins" fresh_ctx
    [
      Gherkin.given "a book \"alpha\" with 5 000 cash" (fun ctx ->
          ctx |> with_cash ~book_id:"alpha" ~cash:"5000");
      Gherkin.when_
        "a cash event with delta +1 (inconsistent) and new_balance 7 500 is recorded"
        (fun ctx -> ctx |> record_cash ~book_id:"alpha" ~delta:"1" ~new_balance:"7500");
      Gherkin.then_ "the view's cash matches new_balance, not the prior balance + delta"
        (fun ctx ->
          let r =
            risk_view_ref_for ctx (Pre_trade_risk.Common.Book_id.of_string "alpha")
          in
          dec_eq "cash" (Decimal.of_int 7_500) (Pre_trade_risk.Risk_view.cash !r));
    ]

let feature =
  Gherkin.feature "Record cash command"
    [ cash_balance_replaced; cash_balance_overwrites_delta_disagreement ]
