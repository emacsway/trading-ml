(** Command pipeline for {!Submit_order_command.t}.

    Composes {!Submit_order_command_handler.handle} with two side
    effects:

    - The originating saga's [correlation_id] is logged in the
      injected {!Order_command_log.S} on [Accepted], keyed by
      [placement_id]. Downstream events generated outside
      command-in-scope (future fill-from-WS) will recover it
      from there.
    - Exactly one of the three integration-event ports fires per
      call:
      - {b Accepted}: broker projected a non-["REJECTED"] view
        model → [publish_accepted].
      - {b Rejected}: broker projected [status = "REJECTED"] →
        [publish_rejected].
      - {b Unreachable}: broker adapter raised (transport, wire
        decode, anything else) → [publish_unreachable].
      - {b Validation failure}: command's wire primitives failed
        to parse → [publish_unreachable] with the concatenated
        reasons (the saga treats a never-submitted order the
        same way as an unreachable broker — release the
        reservation).

    Account's compensation handler on {!Order_rejected} /
    {!Order_unreachable} relies on the one-port-per-call invariant
    for correct rollback.

    The workflow is bus-agnostic: it depends on plain
    [_ -> unit] ports, not on any specific transport.

    The [Rop.t] return surfaces the validation error list to
    callers that want to log it (the bus subscriber today
    discards it — the IE has already been published). *)

module Order_accepted :
    module type of Broker_integration_events.Order_accepted_integration_event

module Order_rejected :
    module type of Broker_integration_events.Order_rejected_integration_event

module Order_unreachable :
    module type of Broker_integration_events.Order_unreachable_integration_event

module type Command_log = Broker_store.Order_command_log.S

val execute :
  broker:Broker.client ->
  command_log:(module Command_log with type t = 'log) ->
  command_log_handle:'log ->
  publish_accepted:(Order_accepted.t -> unit) ->
  publish_rejected:(Order_rejected.t -> unit) ->
  publish_unreachable:(Order_unreachable.t -> unit) ->
  Submit_order_command.t ->
  (unit, Submit_order_command_handler.handle_error) Rop.t
