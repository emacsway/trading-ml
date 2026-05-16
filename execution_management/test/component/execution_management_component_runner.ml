(** Component test runner for Execution_management BC. *)

let () =
  Alcotest.run "trading-execution-management-component" [ Open_order_ticket_saga_test.feature ]
