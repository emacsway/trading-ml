(** Integration event: Account refused to reserve — invariant
    violation (insufficient cash for a buy, insufficient quantity
    for a sell). Published by {!Reserve_command_workflow} when
    {!Account.Portfolio.try_reserve} returns
    [Insufficient_cash] / [Insufficient_qty].

    No [reservation_id]: nothing was created. Audit and SSE
    consumers still get the attempt context (side / instrument /
    quantity) plus a free-form [reason] string for reporting. *)

include module type of Reservation_rejected_integration_event_t
include module type of Reservation_rejected_integration_event_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
