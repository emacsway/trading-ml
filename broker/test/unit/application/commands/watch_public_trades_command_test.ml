(** Sociable tests for the public-trade (tape) subscription commands.

    Exercised against an in-process fake of the {!Broker.S} port that
    records the [subscribe] / [unsubscribe] requests it receives, so the
    test asserts the command translates into exactly the
    [Subscribe_public_trades] request for the parsed instrument — and that
    a malformed symbol is refused with no port call at all. *)

open Core
module Watch = Broker_commands.Watch_public_trades_command
module Watch_wf = Broker_commands.Watch_public_trades_command_workflow
module Watch_h = Broker_commands.Watch_public_trades_command_handler
module Unwatch = Broker_commands.Unwatch_public_trades_command
module Unwatch_wf = Broker_commands.Unwatch_public_trades_command_workflow

module Fake_broker = struct
  type t = {
    mutable subscribed : Broker.request list;
    mutable unsubscribed : Broker.request list;
  }

  let create () = { subscribed = []; unsubscribed = [] }
  let name = "fake"
  let venues _ = []
  let bars _ ~n:_ ~instrument:_ ~timeframe:_ = []

  let place_order _ ~placement_id:_ ~instrument:_ ~side:_ ~quantity:_ ~kind:_ ~tif:_ =
    failwith "fake: place_order not used"

  let cancel_order _ ~placement_id:_ = None
  let get_order _ ~placement_id:_ = None
  let get_trades _ ~placement_id:_ = []
  let start_live_feed _ ~sw:_ ~env:_ ~on_event:_ = ()
  let subscribe t (r : Broker.request) = t.subscribed <- r :: t.subscribed
  let unsubscribe t (r : Broker.request) = t.unsubscribed <- r :: t.unsubscribed
end

let fake_client (fb : Fake_broker.t) : Broker.client = Broker.make (module Fake_broker) fb

let sber = "SBER@MISX"

(* A request matches [Subscribe_public_trades] for [qualified] iff it is
   that variant and its instrument round-trips to the same qualified name. *)
let is_tape_request ~qualified (r : Broker.request) =
  match r with
  | Broker.Subscribe_public_trades { instrument } ->
      Instrument.to_qualified instrument = qualified
  | _ -> false

let test_watch_subscribes_public_trades () =
  let fb = Fake_broker.create () in
  let result = Watch_wf.execute ~broker:(fake_client fb) { symbol = sber } in
  Alcotest.(check bool) "workflow Ok" true (Result.is_ok result);
  Alcotest.(check int) "subscribe called once" 1 (List.length fb.subscribed);
  Alcotest.(check bool)
    "subscribe is Subscribe_public_trades for SBER@MISX" true
    (List.for_all (is_tape_request ~qualified:sber) fb.subscribed);
  Alcotest.(check int) "no unsubscribe" 0 (List.length fb.unsubscribed)

let test_unwatch_unsubscribes_public_trades () =
  let fb = Fake_broker.create () in
  let result = Unwatch_wf.execute ~broker:(fake_client fb) { symbol = sber } in
  Alcotest.(check bool) "workflow Ok" true (Result.is_ok result);
  Alcotest.(check int) "unsubscribe called once" 1 (List.length fb.unsubscribed);
  Alcotest.(check bool)
    "unsubscribe is Subscribe_public_trades for SBER@MISX" true
    (List.for_all (is_tape_request ~qualified:sber) fb.unsubscribed);
  Alcotest.(check int) "no subscribe" 0 (List.length fb.subscribed)

let test_malformed_symbol_is_refused_with_no_port_call () =
  let fb = Fake_broker.create () in
  let result = Watch_wf.execute ~broker:(fake_client fb) { symbol = "bad" } in
  (match result with
  | Error [ Watch_h.Validation (Watch_h.Invalid_symbol "bad") ] -> ()
  | _ -> Alcotest.fail "expected Invalid_symbol refusal");
  Alcotest.(check int) "no subscribe on a refused command" 0 (List.length fb.subscribed)

let tests =
  [
    ("watch subscribes the public tape", `Quick, test_watch_subscribes_public_trades);
    ( "unwatch unsubscribes the public tape",
      `Quick,
      test_unwatch_unsubscribes_public_trades );
    ( "malformed symbol is refused with no port call",
      `Quick,
      test_malformed_symbol_is_refused_with_no_port_call );
  ]
