let () =
  Alcotest.run "trading-order-management-unit"
    [ ("order_process_manager", Order_process_manager_test.tests) ]
