(** Unit test runner for the Order_flow BC. Mirrors {!order_flow/lib/}. *)

let () = Alcotest.run "trading-order_flow-unit" [ ("footprint", Footprint_test.tests) ]
