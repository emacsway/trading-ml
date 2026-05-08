module Order_unreachable = Order_unreachable_integration_event

let handle
    ~(dispatch_release : correlation_id:string -> reservation_id:int -> unit)
    (ev : Order_unreachable.t) : unit =
  dispatch_release ~correlation_id:ev.Order_unreachable.correlation_id
    ~reservation_id:ev.Order_unreachable.reservation_id
