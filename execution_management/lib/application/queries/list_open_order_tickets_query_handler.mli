(** Handler for {!List_open_order_tickets_query}. Reads from the
    ticket_store port and projects each non-terminal ticket via
    {!Order_ticket_view_model.of_domain}. Order is unspecified
    (delegated to the store's [all_open]). *)

module Ports = Execution_management_ports

val handle :
  (module Ports.Ticket_store.S with type t = 's) ->
  store_handle:'s ->
  List_open_order_tickets_query.t ->
  Order_ticket_view_model.t list
