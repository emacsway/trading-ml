module Amount_reserved = Account_integration_events.Amount_reserved_integration_event

let handle
    ~(publish_amount_reserved : Amount_reserved.t -> unit)
    ~(correlation_id : string)
    (ev : Account.Portfolio.Events.Amount_reserved.t) : unit =
  publish_amount_reserved (Amount_reserved.of_domain ~correlation_id ev)
