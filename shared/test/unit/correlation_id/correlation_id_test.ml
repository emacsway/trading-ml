(** Unit tests for {!Correlation_id}. *)

let test_of_string_rejects_empty () =
  Alcotest.check_raises "empty" (Invalid_argument "Correlation_id.of_string: empty")
    (fun () -> ignore (Correlation_id.of_string ""))

let test_of_string_accepts_arbitrary () =
  let id = Correlation_id.of_string "user-supplied-id" in
  Alcotest.(check string) "verbatim" "user-supplied-id" (Correlation_id.to_string id)

let test_generate_is_uuid_v4_shape () =
  let id = Correlation_id.generate () in
  let s = Correlation_id.to_string id in
  (* Format: 8-4-4-4-12 hex digits, length 36. *)
  Alcotest.(check int) "length" 36 (String.length s);
  Alcotest.(check char) "dash@8" '-' s.[8];
  Alcotest.(check char) "dash@13" '-' s.[13];
  Alcotest.(check char) "dash@18" '-' s.[18];
  Alcotest.(check char) "dash@23" '-' s.[23];
  Alcotest.(check char) "v4 marker" '4' s.[14]

let test_generate_uniqueness () =
  let a = Correlation_id.generate () in
  let b = Correlation_id.generate () in
  Alcotest.(check bool) "distinct" false (Correlation_id.equal a b)

let test_equal_compare_hash () =
  let a = Correlation_id.of_string "abc" in
  let b = Correlation_id.of_string "abc" in
  let c = Correlation_id.of_string "abd" in
  Alcotest.(check bool) "equal a b" true (Correlation_id.equal a b);
  Alcotest.(check bool) "not equal a c" false (Correlation_id.equal a c);
  Alcotest.(check int) "compare a b" 0 (Correlation_id.compare a b);
  Alcotest.(check bool) "compare a c < 0" true (Correlation_id.compare a c < 0);
  Alcotest.(check int) "hash equal" (Correlation_id.hash a) (Correlation_id.hash b)

let tests =
  [
    Alcotest.test_case "of_string rejects empty" `Quick test_of_string_rejects_empty;
    Alcotest.test_case "of_string accepts arbitrary" `Quick
      test_of_string_accepts_arbitrary;
    Alcotest.test_case "generate is UUIDv4 shape" `Quick test_generate_is_uuid_v4_shape;
    Alcotest.test_case "generate uniqueness" `Quick test_generate_uniqueness;
    Alcotest.test_case "equal/compare/hash" `Quick test_equal_compare_hash;
  ]
