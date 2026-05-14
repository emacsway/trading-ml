module Order_cancelled = Paper_broker_integration_events.Order_cancelled_integration_event

module type Store = Paper_broker_store.Order_store.S
module type Command_log = Paper_broker_store.Order_command_log.S

let execute
    (type store log)
    ~(store : (module Store with type t = store))
    ~(store_handle : store)
    ~(command_log : (module Command_log with type t = log))
    ~(command_log_handle : log)
    ~(now_ts : unit -> int64)
    ~(publish_order_cancelled : Order_cancelled.t -> unit)
    (cmd : Cancel_pending_order_command.t) :
    (unit, Cancel_pending_order_command_handler.handle_error) Rop.t =
  let module L = (val command_log : Command_log with type t = log) in
  match Cancel_pending_order_command_handler.handle ~store ~store_handle ~now_ts cmd with
  | Ok { order; event } ->
      L.record_cancel command_log_handle ~aggregate_id:order.id
        ~correlation_id:cmd.correlation_id;
      Paper_broker_domain_event_handlers.Publish_integration_event_on_order_cancelled
      .handle ~publish_order_cancelled ~correlation_id:cmd.correlation_id event;
      Rop.succeed ()
  | Error errs -> Error errs
