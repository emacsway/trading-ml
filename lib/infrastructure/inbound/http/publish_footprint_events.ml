module Footprint_completed =
  Order_flow_integration_events.Footprint_completed_integration_event
module Instrument_vm = Order_flow_view_models.Instrument_view_model

(* Qualified symbol from the integration event's nested instrument view
   model — TICKER@MIC, with /BOARD appended when present — matching
   Instrument.to_qualified and the key the order_flow read-model and the
   [?footprints=] query parser both use. *)
let qualified (i : Instrument_vm.t) =
  i.Instrument_vm.ticker ^ "@" ^ i.Instrument_vm.venue
  ^
  match i.Instrument_vm.board with
  | Some b -> "/" ^ b
  | None -> ""

(** Bus consumer for [order-flow.footprint-completed]: route one sealed
    footprint to the SSE [footprint] channel, keyed by its
    [(qualified symbol, boundary token)]. The token rides the event's
    [timeframe] field ("M5", "VOL:1000"); the payload sent on is the
    event's own DTO, so the pull ([/api/footprints]) and push (here)
    sides serve byte-identical shapes. *)
let handle ~registry (ev : Footprint_completed.t) : unit =
  let key =
    Stream.footprint_key
      ~symbol:(qualified ev.Footprint_completed.instrument)
      ~token:ev.Footprint_completed.timeframe
  in
  Stream.push_footprint registry ~key (Footprint_completed.yojson_of_t ev)
