open Core

(** Private JSON projection of {!Broker_domain.Order.t} for the
    venue-keyed HTTP UI. Stays here (not in
    {!Broker_view_models.Order_view_model}) because it surfaces
    venue-native handles ([client_order_id], [id], [exec_id]) that
    the application-layer view model deliberately omits — those
    handles are private to each ACL adapter, and exposing them on
    the wire is a property of this legacy debug surface only.

    Will be removed alongside this HTTP route family; new callers
    should consume the bus-published [Order_view_model.t] keyed by
    [placement_id]. *)
let order_json (o : Order.t) : Yojson.Safe.t =
  let kind_obj : Yojson.Safe.t =
    match o.kind with
    | Order.Market -> `Assoc [ ("type", `String "MARKET") ]
    | Order.Limit p ->
        `Assoc [ ("type", `String "LIMIT"); ("price", `String (Decimal.to_string p)) ]
    | Order.Stop p ->
        `Assoc [ ("type", `String "STOP"); ("price", `String (Decimal.to_string p)) ]
    | Order.Stop_limit { stop; limit } ->
        `Assoc
          [
            ("type", `String "STOP_LIMIT");
            ("stop_price", `String (Decimal.to_string stop));
            ("limit_price", `String (Decimal.to_string limit));
          ]
  in
  `Assoc
    [
      ("id", `String o.id);
      ("exec_id", `String o.exec_id);
      ("client_order_id", `String o.client_order_id);
      ("instrument", `String (Instrument.to_qualified o.instrument));
      ("side", `String (Side.to_string o.side));
      ("quantity", `String (Decimal.to_string o.quantity));
      ("filled", `String (Decimal.to_string o.filled));
      ("remaining", `String (Decimal.to_string o.remaining));
      ("kind", kind_obj);
      ("tif", `String (Order.tif_to_string o.tif));
      ("status", `String (Order.status_to_string o.status));
      ("created_ts", `Int (Int64.to_int o.created_ts));
    ]

let orders_json (os : Order.t list) : Yojson.Safe.t =
  `Assoc [ ("orders", `List (List.map order_json os)) ]

let exchanges_json (broker : Broker.client) : Yojson.Safe.t =
  let venues =
    try Broker.venues broker
    with e ->
      Log.warn "%s venues failed: %s" (Broker.name broker) (Printexc.to_string e);
      []
  in
  `Assoc [ ("exchanges", `List (List.map (fun m -> `String (Mic.to_string m)) venues)) ]

let orders_prefix = "/api/orders/"

let strip_orders_prefix path =
  let plen = String.length orders_prefix in
  if String.length path > plen && String.sub path 0 plen = orders_prefix then
    Some (String.sub path plen (String.length path - plen))
  else None

let make_handler ~broker : Inbound_http.Route.handler =
 fun request _body ->
  let uri = Cohttp.Request.uri request in
  let path = Uri.path uri in
  let meth = Cohttp.Request.meth request in
  let json j = Some (200, `Response (Inbound_http.Response.json ~status:`OK j)) in
  match (meth, path) with
  | `GET, "/api/orders" -> json (orders_json (Broker.get_orders broker))
  | `GET, "/api/exchanges" -> json (exchanges_json broker)
  | `GET, _ -> (
      match strip_orders_prefix path with
      | Some cid -> json (order_json (Broker.get_order broker ~client_order_id:cid))
      | None -> None)
  | `DELETE, _ -> (
      match strip_orders_prefix path with
      | Some cid -> json (order_json (Broker.cancel_order broker ~client_order_id:cid))
      | None -> None)
  | _ -> None
