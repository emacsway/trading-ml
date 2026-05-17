type t = {
  ticket_id : Values.Ticket_id.t;
  reservation_id : Values.Reservation_id.t;
  progress : Values.Progress.t;
  occurred_at : int64;
}

let make ~ticket_id ~reservation_id ~progress ~occurred_at =
  { ticket_id; reservation_id; progress; occurred_at }
