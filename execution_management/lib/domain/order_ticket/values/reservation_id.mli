(** Account-side reservation identity carried by every OrderTicket.

    Distinct from {!Ticket_id} on purpose: the ticket is the EMS-side
    aggregate identity (used for the ticket_store, for the wire
    placement_id encoding, for operator queries), while the
    reservation_id is the Account-side identity of the cash
    earmark that backs the ticket. Today the application layer
    creates them with the same numeric value (one reservation
    backs one ticket), but the types stay separate so a future
    one-to-many or different-id-space model lands without
    refactoring the aggregate. *)

type t = private int

val of_int : int -> t
(** Raises [Invalid_argument] when [n <= 0]. *)
(*@ r = of_int n
    requires n > 0
    ensures (r : int) = n *)

val to_int : t -> int
val equal : t -> t -> bool
val compare : t -> t -> int
