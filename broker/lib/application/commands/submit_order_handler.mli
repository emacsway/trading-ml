(** Synchronous handler for {!Submit_order_command.t}.

    Single function {!make} encapsulates the full lifecycle of a
    submission: parse the wire DTO into domain types, call the
    outbound {!Broker.client} port, classify the result, publish
    exactly one {!Broker_integration_events.Order_event.t}.

    {b Outcomes.}
    - [place_order] returns an order with [status = Rejected] →
      publish {!Order_rejected}.
    - [place_order] returns any other status (typical [New] /
      [Pending_new], or already partially / fully filled on
      aggressive orders) → publish {!Order_accepted}.
    - [place_order] raises (transport error, broker unreachable,
      malformed DTO that slipped past HTTP validation) → publish
      {!Order_unreachable}.

    {b Choreography contract.} Exactly one event published per
    call. Account's compensation subscriber relies on this for
    reservation release. Adding a path that publishes zero or
    multiple events breaks the choreography. *)

val make :
  broker:Broker.client ->
  events:Broker_integration_events.Order_event.t Bus.Event_bus.t ->
  Submit_order_command.t ->
  unit
(** Curry-friendly signature for {!Bus.Command_bus.register_handler}:
    the composition root partially applies [~broker] and [~events],
    yielding [Submit_order_command.t -> unit]. *)
