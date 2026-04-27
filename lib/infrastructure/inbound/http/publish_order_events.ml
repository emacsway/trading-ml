(** Publisher: projects {!Workflows.Place_order_workflow.event} values to
    JSON via [Integration_events.*] DTOs and pushes each one to the SSE
    [order] channel via {!Stream.publish_order}.

    Wraps every event in a discriminated envelope:
    [{ "kind": <variant>, "payload": <integration-event-dto> }]
    The browser-side [addEventListener("order", ...)] handler branches
    on [kind] to decide which UI region updates. *)

let json_of_event : Workflows.Place_order_workflow.event -> Yojson.Safe.t = function
  | Amount_reserved x ->
      let module IE = Integration_events.Amount_reserved_integration_event in
      `Assoc
        [
          ("kind", `String "amount_reserved"); ("payload", IE.yojson_of_t (IE.of_domain x));
        ]
  | Order_forwarded x ->
      let module IE = Integration_events.Order_forwarded_integration_event in
      `Assoc
        [
          ("kind", `String "order_forwarded"); ("payload", IE.yojson_of_t (IE.of_domain x));
        ]
  | Forward_rejected x ->
      let module IE = Integration_events.Forward_rejected_integration_event in
      `Assoc
        [
          ("kind", `String "forward_rejected");
          ("payload", IE.yojson_of_t (IE.of_domain x));
        ]
  | Reservation_released x ->
      let module IE = Integration_events.Reservation_released_integration_event in
      `Assoc
        [
          ("kind", `String "reservation_released");
          ("payload", IE.yojson_of_t (IE.of_domain x));
        ]

let publish (registry : Stream.t) (events : Workflows.Place_order_workflow.event list) :
    unit =
  List.iter (fun e -> Stream.publish_order registry (json_of_event e)) events
