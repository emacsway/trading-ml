let () =
  Alcotest.run "trading-paper-broker-unit" [ ("slippage", Slippage_test.tests) ]
