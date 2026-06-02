(** Unit tests for the footprint demand registry — the two-level refcount
    that drives both boundary fan-out and cross-BC tape demand. *)

open Core
module Registry = Order_flow_subscription.Footprint_subscription_registry
module Bar_boundary = Order_flow.Footprint.Values.Bar_boundary

let m1 = Bar_boundary.Time Timeframe.M1
let m5 = Bar_boundary.Time Timeframe.M5
let sber = Instrument.of_qualified "SBER@MISX"
let gazp = Instrument.of_qualified "GAZP@MISX"
let default_boundary = m5

let fresh () = Registry.create ~default_boundary

let tokens_of bs = List.sort compare (List.map Bar_boundary.to_token bs)

let test_default_always_in_fan_out () =
  let r = fresh () in
  (* Nothing watched: only the default boundary is fanned into. *)
  Alcotest.(check (list string))
    "default only" [ "M5" ]
    (tokens_of (Registry.boundaries_for r "SBER@MISX"))

let test_watch_adds_boundary_to_fan_out () =
  let r = fresh () in
  let _ = Registry.watch r ~instrument:sber ~boundary:m1 in
  Alcotest.(check (list string))
    "default + watched M1" [ "M1"; "M5" ]
    (tokens_of (Registry.boundaries_for r "SBER@MISX"));
  (* Other instruments are unaffected — still default only. *)
  Alcotest.(check (list string))
    "GAZP still default only" [ "M5" ]
    (tokens_of (Registry.boundaries_for r "GAZP@MISX"))

let test_watching_the_default_does_not_duplicate () =
  let r = fresh () in
  let _ = Registry.watch r ~instrument:sber ~boundary:m5 in
  Alcotest.(check (list string))
    "no duplicate M5" [ "M5" ]
    (tokens_of (Registry.boundaries_for r "SBER@MISX"))

let test_instrument_level_transition_first_and_last () =
  let r = fresh () in
  (* First boundary for SBER -> First_for_instrument (pull the tape). *)
  (match Registry.watch r ~instrument:sber ~boundary:m1 with
  | Registry.First_for_instrument -> ()
  | Registry.Already_watching ->
      Alcotest.fail "first watch should be First_for_instrument");
  (* A second, different boundary for SBER -> Already_watching (tape already up). *)
  (match Registry.watch r ~instrument:sber ~boundary:m5 with
  | Registry.Already_watching -> ()
  | Registry.First_for_instrument ->
      Alcotest.fail "second boundary should be Already_watching");
  (* Dropping one of two boundaries -> Still_watching (tape stays). *)
  (match Registry.unwatch r ~instrument:sber ~boundary:m1 with
  | Registry.Still_watching -> ()
  | Registry.Last_for_instrument -> Alcotest.fail "still one boundary left");
  (* Dropping the last boundary -> Last_for_instrument (release the tape). *)
  match Registry.unwatch r ~instrument:sber ~boundary:m5 with
  | Registry.Last_for_instrument -> ()
  | Registry.Still_watching -> Alcotest.fail "last boundary should be Last_for_instrument"

let test_boundary_refcount_shares_one_feed () =
  let r = fresh () in
  (* Two watchers of the SAME (SBER, M1): first is First_for_instrument,
     the second is Already_watching, and one unwatch must NOT drop it. *)
  let _ = Registry.watch r ~instrument:sber ~boundary:m1 in
  (match Registry.watch r ~instrument:sber ~boundary:m1 with
  | Registry.Already_watching -> ()
  | Registry.First_for_instrument ->
      Alcotest.fail "second watcher of same feed is not first");
  (match Registry.unwatch r ~instrument:sber ~boundary:m1 with
  | Registry.Still_watching -> ()
  | Registry.Last_for_instrument -> Alcotest.fail "one watcher remains, not last");
  Alcotest.(check (list string))
    "M1 still fanned while one watcher holds it" [ "M1"; "M5" ]
    (tokens_of (Registry.boundaries_for r "SBER@MISX"));
  (* The final watcher drops it -> last, and M1 leaves the fan-out. *)
  (match Registry.unwatch r ~instrument:sber ~boundary:m1 with
  | Registry.Last_for_instrument -> ()
  | Registry.Still_watching -> Alcotest.fail "final watcher should be last");
  Alcotest.(check (list string))
    "back to default only" [ "M5" ]
    (tokens_of (Registry.boundaries_for r "SBER@MISX"))

let test_unwatch_unknown_is_benign () =
  let r = fresh () in
  (match Registry.unwatch r ~instrument:gazp ~boundary:m1 with
  | Registry.Still_watching -> ()
  | Registry.Last_for_instrument ->
      Alcotest.fail "unwatch with no prior watch must not report last");
  Alcotest.(check (list string))
    "fan-out unchanged" [ "M5" ]
    (tokens_of (Registry.boundaries_for r "GAZP@MISX"))

let tests =
  [
    ("default boundary is always fanned into", `Quick, test_default_always_in_fan_out);
    ( "a watch adds its boundary to the fan-out",
      `Quick,
      test_watch_adds_boundary_to_fan_out );
    ( "watching the default does not duplicate it",
      `Quick,
      test_watching_the_default_does_not_duplicate );
    ( "instrument-level transitions report first and last",
      `Quick,
      test_instrument_level_transition_first_and_last );
    ( "boundary refcount shares one feed across watchers",
      `Quick,
      test_boundary_refcount_shares_one_feed );
    ("unwatch with no prior watch is benign", `Quick, test_unwatch_unknown_is_benign);
  ]
