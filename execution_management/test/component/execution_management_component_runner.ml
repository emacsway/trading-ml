(** Component test runner for Execution_management BC. *)

let () =
  Alcotest.run "trading-execution-management-component"
    [ Order_ticket_cancel_test.feature ]
