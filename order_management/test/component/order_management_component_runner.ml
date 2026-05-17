(** Component test runner for Order_management BC. *)

let () =
  Alcotest.run "trading-order-management-component"
    [ Order_process_manager_saga_test.feature ]
