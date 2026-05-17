(** Handler for {!Get_order_ticket_query}. Reads from the
    ticket_store port and projects via
    {!Order_ticket_view_model.of_domain}. Returns [None] when the
    ticket id is unknown to the store (or the id is malformed). *)

module Ports = Execution_management_ports

val handle :
  (module Ports.Ticket_store.S with type t = 's) ->
  store_handle:'s ->
  Get_order_ticket_query.t ->
  Order_ticket_view_model.t option
