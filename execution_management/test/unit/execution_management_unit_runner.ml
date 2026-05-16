let () =
  Alcotest.run "trading-execution-management-unit"
    [
      ("kill_switch", Kill_switch_test.tests);
      ("rate_limit", Rate_limit_test.tests);
      ("open_order_ticket_process", Open_order_ticket_process_test.tests);
    ]
