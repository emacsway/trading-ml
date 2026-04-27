open Core

let parse_side = function
  | "BUY" -> Side.Buy
  | "SELL" -> Side.Sell
  | s -> invalid_arg (Printf.sprintf "side: %S" s)

let parse_tif = function
  | "GTC" -> Order.GTC
  | "DAY" -> Order.DAY
  | "IOC" -> Order.IOC
  | "FOK" -> Order.FOK
  | s -> invalid_arg (Printf.sprintf "tif: %S" s)

let parse_kind (k : Queries.Order_kind_view_model.t) : Order.kind =
  match String.uppercase_ascii k.type_ with
  | "MARKET" -> Market
  | "LIMIT" -> (
      match k.price with
      | Some p -> Limit (Decimal.of_float p)
      | None -> invalid_arg "LIMIT: missing price")
  | "STOP" -> (
      match k.price with
      | Some p -> Stop (Decimal.of_float p)
      | None -> invalid_arg "STOP: missing price")
  | "STOP_LIMIT" -> (
      match (k.stop_price, k.limit_price) with
      | Some s, Some l ->
          Stop_limit { stop = Decimal.of_float s; limit = Decimal.of_float l }
      | _ -> invalid_arg "STOP_LIMIT: missing stop_price/limit_price")
  | other -> invalid_arg (Printf.sprintf "kind: %S" other)

let parse_args (cmd : Submit_order_command.t) =
  Instrument.of_qualified cmd.symbol,
  parse_side (String.uppercase_ascii cmd.side),
  Decimal.of_float cmd.quantity,
  parse_kind cmd.kind,
  parse_tif (String.uppercase_ascii cmd.tif)

let make ~(broker : Broker.client)
    ~(events : Broker_integration_events.Order_event.t Bus.Event_bus.t)
    (cmd : Submit_order_command.t) : unit =
  let cid = cmd.client_order_id in
  let publish ev = Bus.Event_bus.publish events ev in
  match
    try Ok (parse_args cmd)
    with Invalid_argument m | Failure m -> Error m
  with
  | Error reason ->
      publish (Order_unreachable { client_order_id = cid; reason })
  | Ok (instrument, side, quantity, kind, tif) -> (
      match
        try
          Ok
            (Broker.place_order broker ~instrument ~side ~quantity ~kind ~tif
               ~client_order_id:cid)
        with e -> Error (Printexc.to_string e)
      with
      | Error reason ->
          publish (Order_unreachable { client_order_id = cid; reason })
      | Ok order -> (
          match order.status with
          | Rejected ->
              publish
                (Order_rejected
                   {
                     client_order_id = cid;
                     reason = Order.status_to_string order.status;
                   })
          | _ ->
              let dto = Queries.Order_view_model.of_domain order in
              publish
                (Order_accepted { client_order_id = cid; broker_order = dto })))
