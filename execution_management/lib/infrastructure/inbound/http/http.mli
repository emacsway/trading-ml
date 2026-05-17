(** Execution_management inbound HTTP routes.

    Routes (PR5):
    - [GET /api/order-tickets]         — list every non-terminal OrderTicket
                                          (serialised [Order_ticket_view_model.t list])
    - [GET /api/order-tickets/{id}]    — fetch a single OrderTicket by id
                                          (404 when unknown)

    Future surfaces: kill-switch reset endpoint, saga-progress SSE
    channel filtered by correlation_id. *)

val make_handler :
  get_order_ticket:(int -> Yojson.Safe.t option) ->
  list_open_order_tickets:(unit -> Yojson.Safe.t list) ->
  unit ->
  Inbound_http.Route.handler
