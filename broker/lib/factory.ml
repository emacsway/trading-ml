open Core

type rest =
  | Finam of { rest : Finam.Rest.t; adapter : Finam.Finam_broker.t }
  | Bcs of Bcs.Rest.t
  | Synthetic

type t = {
  client : Broker.client;
  market_price : instrument:Instrument.t -> Decimal.t;
  ws_setup : (sw:Eio.Switch.t -> Server.Http.live_setup) option;
  http_handler : Inbound_http.Route.handler;
}

(** Build a {!Server.Http.live_setup} that bridges Finam's WebSocket
    feed into the SSE stream registry and into the bar-updated bus
    publisher. Connection happens up-front on the server's switch;
    per-key SUBSCRIBE/UNSUBSCRIBE messages flow on subscriber
    lifecycle hooks; inbound BARS events fan out via
    [Stream.push_from_upstream] and [publish_bar_updated]. *)
let finam_live_setup
    ~env
    ~publish_bar_updated
    ~publish_order_filled
    ~origin_correlation_id
    ~(finam : Finam.Finam_broker.t)
    (rest : Finam.Rest.t)
    ~sw : Server.Http.live_setup =
  let cfg = Finam.Rest.cfg rest in
  let auth = Finam.Rest.auth rest in
  let registry_ref : Server.Stream.t option ref = ref None in
  let bridge_ref : Finam.Ws_bridge.bridge option ref = ref None in
  (* Per-placement cumulative-fill accumulator. Finam ships each
     execution leg separately; [new_total_filled] is the sum of
     [fill_quantity] across every observed [trade_update] for the
     same [placement_id]. Lives in process memory — survives only
     the adapter's lifetime, replayed on reconnect from the
     venue if needed via REST. *)
  let total_filled : (int, Decimal.t) Hashtbl.t = Hashtbl.create 16 in
  let bump_total ~placement_id ~delta =
    let prev =
      match Hashtbl.find_opt total_filled placement_id with
      | Some d -> d
      | None -> Decimal.zero
    in
    let next = Decimal.add prev delta in
    Hashtbl.replace total_filled placement_id next;
    next
  in
  let handle_trade (tu : Finam.Ws.trade_update) =
    match Finam.Finam_broker.placement_id_by_order_id finam ~order_id:tu.order_id with
    | None ->
        Log.warn "[finam ws] trade for unknown order_id=%s — skipping" tu.order_id
    | Some placement_id -> (
        match origin_correlation_id ~placement_id with
        | None ->
            Log.warn
              "[finam ws] trade for placement_id=%d has no Submit correlation_id; \
               skipping"
              placement_id
        | Some correlation_id ->
            let new_total = bump_total ~placement_id ~delta:tu.quantity in
            let ie : Broker_integration_events.Order_filled_integration_event.t =
              {
                correlation_id;
                placement_id;
                id = tu.order_id;
                exec_id = tu.trade_id;
                instrument =
                  Broker_view_models.Instrument_view_model.of_domain tu.instrument;
                side = Side.to_string tu.side;
                fill_quantity = Decimal.to_string tu.quantity;
                fill_price = Decimal.to_string tu.price;
                fee = "0";
                new_total_filled = Decimal.to_string new_total;
                fill_ts = Datetime.Iso8601.format tu.ts;
              }
            in
            publish_order_filled ie)
  in
  let on_event (ev : Finam.Ws.event) =
    match ev with
    | Bars { instrument; timeframe; bars } ->
        let tfs : Timeframe.t list =
          match timeframe with
          | Some tf -> [ tf ]
          | None -> (
              match !bridge_ref with
              | None -> []
              | Some b -> Finam.Ws_bridge.timeframes_for_instrument b instrument)
        in
        List.iter
          (fun (tf : Timeframe.t) ->
            List.iter
              (fun (candle : Candle.t) ->
                (match !registry_ref with
                | Some r ->
                    Server.Stream.push_from_upstream r ~instrument ~timeframe:tf candle
                | None -> ());
                publish_bar_updated
                  (Broker_integration_events.Bar_updated_integration_event.of_domain
                     ~instrument ~timeframe:tf ~candle))
              bars)
          tfs
    | Trades trades -> List.iter handle_trade trades
    | Error_ev { code; type_; message } ->
        Log.warn "[finam ws] error %d %s: %s" code type_ message
    | Lifecycle { event; code; reason } ->
        Log.info "[finam ws] %s (%d) %s" event code reason
    | _ -> ()
  in
  let bridge = Finam.Ws_bridge.make ~env ~sw ~cfg ~auth ~on_event in
  bridge_ref := Some bridge;
  (* Always-on trade subscription for the broker's account, so
     fills observed at the venue surface as Order_filled IEs
     without waiting for any per-instrument subscriber. *)
  (try
     Finam.Ws_bridge.subscribe_trades bridge
       ~account_id:(Finam.Finam_broker.account_id finam)
   with e ->
     Log.warn "[finam ws] subscribe_trades failed: %s" (Printexc.to_string e));
  Server.Http.
    {
      on_first =
        (fun ~instrument ~timeframe ->
          try Finam.Ws_bridge.subscribe_bars bridge ~instrument ~timeframe
          with e -> Log.warn "[finam ws] subscribe failed: %s" (Printexc.to_string e));
      on_last =
        (fun ~instrument ~timeframe ->
          try Finam.Ws_bridge.unsubscribe_bars bridge ~instrument ~timeframe
          with e -> Log.warn "[finam ws] unsubscribe failed: %s" (Printexc.to_string e));
      bind = (fun r -> registry_ref := Some r);
    }

(** Build a {!Server.Http.live_setup} for BCS. Unlike Finam, BCS
    opens one socket per subscription, so the bridge defers connect
    to [on_first] and tears down on [on_last]. The BARS fan-out
    callback pushes directly into the registry via
    [Stream.push_from_upstream] and into [publish_bar_updated]. *)
let bcs_live_setup ~env ~publish_bar_updated (rest : Bcs.Rest.t) ~sw :
    Server.Http.live_setup =
  let cfg = Bcs.Rest.cfg rest in
  let auth = Bcs.Rest.auth rest in
  let bridge = Bcs.Ws_bridge.make ~env ~sw ~cfg ~auth in
  let registry_ref : Server.Stream.t option ref = ref None in
  let push instrument timeframe candle =
    (match !registry_ref with
    | Some r -> Server.Stream.push_from_upstream r ~instrument ~timeframe candle
    | None -> ());
    publish_bar_updated
      (Broker_integration_events.Bar_updated_integration_event.of_domain ~instrument
         ~timeframe ~candle)
  in
  Server.Http.
    {
      on_first =
        (fun ~instrument ~timeframe ->
          try Bcs.Ws_bridge.subscribe_bars bridge ~instrument ~timeframe ~on_candle:push
          with e -> Log.warn "[bcs ws] subscribe failed: %s" (Printexc.to_string e));
      on_last =
        (fun ~instrument ~timeframe ->
          try Bcs.Ws_bridge.unsubscribe_bars bridge ~instrument ~timeframe
          with e -> Log.warn "[bcs ws] unsubscribe failed: %s" (Printexc.to_string e));
      bind = (fun r -> registry_ref := Some r);
    }

let build ~bus ~env ~now ~source_client ~rest ~paper_mode : t =
  let client = source_client in
  let now_ts : unit -> int64 = now in
  let market_price ~instrument =
    match Broker.bars client ~n:1 ~instrument ~timeframe:Timeframe.H1 with
    | last :: _ -> last.close
    | [] -> Decimal.zero
  in
  let produce (type a) ~uri ~(yojson_of : a -> Yojson.Safe.t) : a -> unit =
    Bus.publish
      (Bus.producer bus ~uri ~serialize:(fun v -> Yojson.Safe.to_string (yojson_of v)))
  in
  let publish_order_accepted =
    produce ~uri:"in-memory://broker.order-accepted"
      ~yojson_of:Broker_integration_events.Order_accepted_integration_event.yojson_of_t
  in
  let publish_order_rejected =
    produce ~uri:"in-memory://broker.order-rejected"
      ~yojson_of:Broker_integration_events.Order_rejected_integration_event.yojson_of_t
  in
  let publish_order_unreachable =
    produce ~uri:"in-memory://broker.order-unreachable"
      ~yojson_of:Broker_integration_events.Order_unreachable_integration_event.yojson_of_t
  in
  let publish_order_cancelled =
    produce ~uri:"in-memory://broker.order-cancelled"
      ~yojson_of:Broker_integration_events.Order_cancelled_integration_event.yojson_of_t
  in
  let publish_bar_updated =
    produce ~uri:"in-memory://broker.bar-updated"
      ~yojson_of:Broker_integration_events.Bar_updated_integration_event.yojson_of_t
  in
  let publish_order_filled =
    produce ~uri:"in-memory://broker.order-filled"
      ~yojson_of:Broker_integration_events.Order_filled_integration_event.yojson_of_t
  in
  (* Process-correlation log: [placement_id ↦ submit/cancel
     correlation_id]. Recorded by Submit on Accepted (and, when
     wired, Cancel); future fill-from-WS events that arrive
     outside command-in-scope will read it back to stamp the
     outbound IE with the originating saga. In-memory for now. *)
  let command_log : Broker_persistence.In_memory_order_command_log.t =
    Broker_persistence.In_memory_order_command_log.create ()
  in
  let command_log_module =
    (module Broker_persistence.In_memory_order_command_log
    : Broker_store.Order_command_log.S
      with type t = Broker_persistence.In_memory_order_command_log.t)
  in
  (* In paper_mode the [paper_broker] BC handles the saga's
     submit_order and cancel_pending_order traffic via its own
     subscriptions. Broker's subscribers would otherwise also
     accept the same wire formats and route them through the live
     source client, which for synthetic/finam/bcs does not really
     place or cancel orders. To avoid double-handling, we skip
     both subscriptions here when paper_mode is on. *)
  (if not paper_mode then
     let dispatch_submit_order (cmd : Broker_commands.Submit_order_command.t) =
       match
         Broker_commands.Submit_order_command_workflow.execute ~broker:client
           ~command_log:command_log_module ~command_log_handle:command_log
           ~publish_accepted:publish_order_accepted
           ~publish_rejected:publish_order_rejected
           ~publish_unreachable:publish_order_unreachable cmd
       with
       | Ok () -> ()
       | Error _ ->
           (* Validation failures already surfaced as Order_unreachable
              IE by the workflow; the Rop tail is discarded. *)
           ()
     in
     let dispatch_cancel_pending_order
         (cmd : Broker_commands.Cancel_pending_order_command.t) =
       match
         Broker_commands.Cancel_pending_order_command_workflow.execute ~broker:client
           ~command_log:command_log_module ~command_log_handle:command_log ~now_ts
           ~publish_order_cancelled cmd
       with
       | Ok () -> ()
       | Error errs ->
           List.iter
             (function
               | Broker_commands.Cancel_pending_order_command_handler.Resolution e ->
                   Log.warn "[broker cancel] %s"
                     (Broker_commands.Cancel_pending_order_command_handler
                      .resolution_error_to_string e))
             errs
     in
     let consume (type a) ~uri ~group ~(t_of_yojson : Yojson.Safe.t -> a) : a Bus.consumer
         =
       Bus.consumer bus ~uri ~group ~deserialize:(fun s ->
           t_of_yojson (Yojson.Safe.from_string s))
     in
     let _ : Bus.subscription =
       Bus.subscribe
         (consume ~uri:"in-memory://broker.submit-order-command" ~group:"broker-saga"
            ~t_of_yojson:Broker_commands.Submit_order_command.t_of_yojson)
         dispatch_submit_order
     in
     let _ : Bus.subscription =
       Bus.subscribe
         (consume ~uri:"in-memory://broker.cancel-pending-order-command"
            ~group:"broker-saga"
            ~t_of_yojson:Broker_commands.Cancel_pending_order_command.t_of_yojson)
         dispatch_cancel_pending_order
     in
     ()
   else
     (* Held in scope so the unused-binding warnings don't fire when
        the publishers and the command log are only consumed by the
        gated branch. Their bus producers remain registered (and
        thus reachable for any future direct caller) regardless of
        [paper_mode]. *)
     let _ =
       ( publish_order_accepted,
         publish_order_rejected,
         publish_order_unreachable,
         publish_order_cancelled,
         command_log,
         now_ts )
     in
     ());
  let origin_correlation_id ~placement_id =
    let module CL = (val command_log_module) in
    CL.origin_correlation_id command_log ~placement_id
  in
  let ws_setup =
    match rest with
    | Finam { rest = r; adapter } ->
        Some
          (finam_live_setup ~env ~publish_bar_updated ~publish_order_filled
             ~origin_correlation_id ~finam:adapter r)
    | Bcs r -> Some (bcs_live_setup ~env ~publish_bar_updated r)
    | Synthetic -> None
  in
  let http_handler = Broker_inbound_http.Http.make_handler ~broker:client in
  { client; market_price; ws_setup; http_handler }
