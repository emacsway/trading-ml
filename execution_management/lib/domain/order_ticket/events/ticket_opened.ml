type t = {
  ticket_id : Values.Ticket_id.t;
  reservation_id : Values.Reservation_id.t;
  intent : Values.Trade_intent.t;
  directive : Values.Execution_directive.t;
  occurred_at : int64;
}

let make ~ticket_id ~reservation_id ~intent ~directive ~occurred_at =
  { ticket_id; reservation_id; intent; directive; occurred_at }
