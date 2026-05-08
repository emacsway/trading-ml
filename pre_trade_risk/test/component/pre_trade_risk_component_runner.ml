(** Component test runner for Pre_trade_risk BC. *)

let () =
  Alcotest.run "trading-pre-trade-risk-component"
    [
      Assess_trade_intent_command_test.feature;
      Record_position_command_test.feature;
      Record_cash_command_test.feature;
    ]
