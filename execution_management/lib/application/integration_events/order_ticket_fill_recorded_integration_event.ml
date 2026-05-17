module Filled = Execution_management.Order_ticket.Events.Placement_filled
module Values = Execution_management.Order_ticket.Values

include Order_ticket_fill_recorded_integration_event_t
include Order_ticket_fill_recorded_integration_event_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

(** Build the IE from the aggregate's [Placement_filled] domain
    event. [reservation_id] is the OrderTicket-level identity
    that backs the placement; the application layer passes it in
    because the [Placement_filled] event itself only carries
    ticket_id + placement_id + fill. *)
let of_domain ~correlation_id ~reservation_id (e : Filled.t) : t =
  let fill = e.fill in
  {
    correlation_id;
    ticket_id = Values.Ticket_id.to_int e.ticket_id;
    reservation_id = Values.Reservation_id.to_int reservation_id;
    fill_quantity = Decimal.to_string fill.quantity;
    fill_price = Decimal.to_string fill.price;
    fee = Decimal.to_string fill.fee;
    occurred_at = Datetime.Iso8601.format fill.ts;
  }
