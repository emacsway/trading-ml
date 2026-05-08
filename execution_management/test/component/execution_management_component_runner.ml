(** Component test runner for Execution_management BC. *)

let () =
  Alcotest.run "trading-execution-management-component" [ Place_order_saga_test.feature ]
