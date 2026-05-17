(** Query: fetch a single OrderTicket snapshot. Returns
    [Order_ticket_view_model.t option] — [None] when no ticket
    with the requested id exists. *)

include module type of Get_order_ticket_query_t

include module type of Get_order_ticket_query_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
