let () =
  Alcotest.run "trading" [
    "decimal", Test_decimal.tests;
    "indicators", Test_indicators.tests;
    "portfolio", Test_portfolio.tests;
    "backtest", Test_backtest.tests;
    "finam dto", Test_finam_dto.tests;
  ]
