module Order_rejected = Order_rejected_integration_event

let handle
    ~(dispatch_release : correlation_id:string -> reservation_id:int -> unit)
    (ev : Order_rejected.t) : unit =
  dispatch_release ~correlation_id:ev.Order_rejected.correlation_id
    ~reservation_id:ev.Order_rejected.reservation_id
