(** HTTP route handlers for execution_management. The factory
    constructs the closures from the typed query handlers and
    closes them over the ticket_store; this module owns only the
    URL routing and JSON shape. *)

let json_response j : Inbound_http.Route.response =
  (200, `Response (Inbound_http.Response.json ~status:`OK j))

let not_found_response () : Inbound_http.Route.response =
  (404, `Response (Inbound_http.Response.json ~status:`Not_found (`Assoc [])))

let parse_ticket_id segment : int option =
  match int_of_string_opt segment with Some n when n > 0 -> Some n | _ -> None

let make_handler ~get_order_ticket ~list_open_order_tickets () :
    Inbound_http.Route.handler =
 fun request _body ->
  let uri = Cohttp.Request.uri request in
  let path = Uri.path uri in
  let meth = Cohttp.Request.meth request in
  match (meth, String.split_on_char '/' path) with
  | `GET, [ ""; "api"; "order-tickets" ] ->
      Some (json_response (`List (list_open_order_tickets ())))
  | `GET, [ ""; "api"; "order-tickets"; segment ] -> (
      match parse_ticket_id segment with
      | None -> Some (not_found_response ())
      | Some ticket_id -> (
          match get_order_ticket ticket_id with
          | None -> Some (not_found_response ())
          | Some j -> Some (json_response j)))
  | _ -> None
