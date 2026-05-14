(** Command pipeline for {!Cancel_pending_order_command.t}.

    Composes the store-side cancel transition from
    {!Cancel_pending_order_command_handler.handle} with:
    - logging the cancel's [correlation_id] in the
      {!Paper_broker_store.Order_command_log.S} (audit / future
      saga compensation),
    - publishing the
      {!Paper_broker_integration_events.Order_cancelled_integration_event.t}
      with the cancel-command's own [correlation_id]. *)

module Order_cancelled :
    module type of Paper_broker_integration_events.Order_cancelled_integration_event

module type Store = Paper_broker_store.Order_store.S
module type Command_log = Paper_broker_store.Order_command_log.S

val execute :
  store:(module Store with type t = 'store) ->
  store_handle:'store ->
  command_log:(module Command_log with type t = 'log) ->
  command_log_handle:'log ->
  now_ts:(unit -> int64) ->
  publish_order_cancelled:(Order_cancelled.t -> unit) ->
  Cancel_pending_order_command.t ->
  (unit, Cancel_pending_order_command_handler.handle_error) Rop.t
