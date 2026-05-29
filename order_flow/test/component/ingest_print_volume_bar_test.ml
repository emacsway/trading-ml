(** Component test: the same ingest-print workflow, unchanged, driving a
    [Volume] boundary end to end. Proves the polymorphic seam (ADR 0032
    §5): the handler / workflow / integration event are boundary-agnostic
    — only [Bar_boundary] and the aggregate's [classify]/[open_] gained a
    [Volume] case, yet the full roll-and-publish cycle works here with no
    other change. *)

open Core
module Workflow = Order_flow_commands.Ingest_print_command_workflow
module Ingest = Order_flow_commands.Ingest_print_command
module Footprint = Order_flow.Footprint
module Bar_boundary = Footprint.Values.Bar_boundary

module Footprint_completed_ie =
  Order_flow_integration_events.Footprint_completed_integration_event

let instrument_qualified = "SBER@MISX"

(* A bar fills to 10 lots of traded volume, regardless of wall-clock. *)
let boundary = Bar_boundary.Volume (Decimal.of_int 10)

let mk_cmd ~price ~size ~ts ~aggressor : Ingest.t =
  { Ingest.symbol = instrument_qualified; price; size; aggressor; ts }

let store : (string, Footprint.t) Hashtbl.t = Hashtbl.create 8
let get_bar instrument = Hashtbl.find_opt store (Instrument.to_qualified instrument)
let put_bar instrument bar =
  Hashtbl.replace store (Instrument.to_qualified instrument) bar
let published : Footprint_completed_ie.t list ref = ref []
let publish_footprint_completed ie = published := ie :: !published

let run_cmd cmd =
  match Workflow.execute ~boundary ~get_bar ~put_bar ~publish_footprint_completed cmd with
  | Ok () -> ()
  | Error _ -> Alcotest.fail "workflow returned error"

let reset () =
  Hashtbl.clear store;
  published := []

(* Volume bar of cap 10: prints of 4 + 6 fill it exactly; the next print
   rolls the bar and publishes one completed footprint carrying the
   accumulated delta. Timestamps are deliberately within one wall-clock
   minute to show time plays no role in a Volume bar's partition. *)
let test_volume_roll_publishes_completed () =
  reset ();
  run_cmd (mk_cmd ~price:"100" ~size:"4" ~ts:"1970-01-01T00:00:00Z" ~aggressor:"BUY");
  run_cmd (mk_cmd ~price:"101" ~size:"6" ~ts:"1970-01-01T00:00:10Z" ~aggressor:"SELL");
  (* bar volume is now 10 = cap; this third print opens a new bar *)
  run_cmd (mk_cmd ~price:"102" ~size:"2" ~ts:"1970-01-01T00:00:20Z" ~aggressor:"BUY");
  Alcotest.(check int) "one completed published" 1 (List.length !published);
  let ie = List.hd !published in
  (* IE decimals are canonical strings (ADR 0007); compare via Decimal
     to stay agnostic to the textual form. *)
  Alcotest.(check bool)
    "completed volume = 10" true
    (Decimal.compare
       (Decimal.of_string ie.Footprint_completed_ie.volume)
       (Decimal.of_int 10)
    = 0);
  (* delta = buy(4) - sell(6) = -2 *)
  Alcotest.(check bool)
    "completed delta = -2" true
    (Decimal.compare
       (Decimal.of_string ie.Footprint_completed_ie.delta)
       (Decimal.of_int (-2))
    = 0)

let tests =
  [
    ("volume bar roll publishes completed", `Quick, test_volume_roll_publishes_completed);
  ]
