(** Query: list every non-terminal OrderTicket. Returns
    [Order_ticket_view_model.t list]. The [book_id] filter slot is
    reserved for a future per-book filter; today the handler
    ignores it and returns everything. *)

include module type of List_open_order_tickets_query_t

include module type of List_open_order_tickets_query_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
