open Core

(** Composition unit for the order_flow BC (ADR 0032).

    Holds the per-instrument forming-bar store (transitional in-memory
    persistence) and subscribes the inbound ACL to the broker's public
    tape on [broker.public-trade-printed]; sealed footprints are published on
    [order-flow.footprint-completed] for the strategy BC to consume.

    No clock dependency: a print carries its own venue timestamp, and the
    Time-bar boundary closes lazily on the first print of the next bucket
    (the clock-driven idle-flush is a deferred refinement, ADR 0032). *)

module Trade_printed_ie =
  Order_flow_external_integration_events.Public_trade_printed_integration_event

module Trade_printed_handler =
  Order_flow_external_integration_events.Public_trade_printed_integration_event_handler

module Footprint = Order_flow.Footprint
module Footprint_completed_ie =
  Order_flow_integration_events.Footprint_completed_integration_event

let build ~bus ?(timeframe = Timeframe.M5) ?boundary () : unit =
  (* Forming bar per instrument, keyed by qualified symbol. *)
  let store : (string, Footprint.t) Hashtbl.t = Hashtbl.create 64 in
  let get_bar instrument = Hashtbl.find_opt store (Instrument.to_qualified instrument) in
  let put_bar instrument bar =
    Hashtbl.replace store (Instrument.to_qualified instrument) bar
  in
  (* [?boundary] overrides the default explicitly — e.g.
     [Bar_boundary.Volume (Decimal.of_int 10_000)] — without the
     composition root touching anything else (ADR 0032 §5). *)
  let boundary =
    match boundary with
    | Some b -> b
    | None -> Footprint.Values.Bar_boundary.Time timeframe
  in
  let publish_footprint_completed =
    Bus.publish
      (Bus.producer bus ~uri:"in-memory://order-flow.footprint-completed"
         ~serialize:(fun v ->
           Yojson.Safe.to_string (Footprint_completed_ie.yojson_of_t v)))
  in
  let consumer =
    Bus.consumer bus ~uri:"in-memory://broker.public-trade-printed"
      ~group:"order-flow-ingest" ~deserialize:(fun s ->
        Trade_printed_ie.t_of_yojson (Yojson.Safe.from_string s))
  in
  let (_ : Bus.subscription) =
    Bus.subscribe consumer
      (Trade_printed_handler.handle ~boundary ~get_bar ~put_bar
         ~publish_footprint_completed)
  in
  ()
