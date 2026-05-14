module Order_accepted = Paper_broker_integration_events.Order_accepted_integration_event

module Order_rejected = Paper_broker_integration_events.Order_rejected_integration_event

module type Store = Paper_broker_store.Order_store.S
module type Command_log = Paper_broker_store.Order_command_log.S

let execute
    (type store log)
    ~(store : (module Store with type t = store))
    ~(store_handle : store)
    ~(command_log : (module Command_log with type t = log))
    ~(command_log_handle : log)
    ~(next_order_id : unit -> string)
    ~(now_ts : unit -> int64)
    ~(placed_after_ts : Core.Instrument.t -> int64)
    ~(publish_order_accepted : Order_accepted.t -> unit)
    ~(publish_order_rejected : Order_rejected.t -> unit)
    (cmd : Submit_order_command.t) :
    (unit, Submit_order_command_handler.handle_error) Rop.t =
  let module L = (val command_log : Command_log with type t = log) in
  match
    Submit_order_command_handler.handle ~store ~store_handle ~next_order_id ~now_ts
      ~placed_after_ts cmd
  with
  | Ok (order, domain_event) ->
      L.record_submit command_log_handle ~aggregate_id:order.id
        ~correlation_id:cmd.correlation_id;
      Paper_broker_domain_event_handlers.Publish_integration_event_on_order_accepted
      .handle ~publish_order_accepted ~correlation_id:cmd.correlation_id domain_event;
      Rop.succeed ()
  | Error errs ->
      let reasons =
        List.filter_map
          (function
            | Submit_order_command_handler.Validation v ->
                Some (Submit_order_command_handler.validation_error_to_string v))
          errs
      in
      let reason = String.concat "; " reasons in
      publish_order_rejected
        Order_rejected.
          {
            correlation_id = cmd.correlation_id;
            reservation_id = cmd.reservation_id;
            reason;
          };
      Error errs
