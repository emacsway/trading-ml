(** Integration event: Account released a previously-reserved
    earmark. Published by {!Release_command_workflow} when
    {!Account.Portfolio.release} returns [Some _] — compensation
    completion. The released cash / quantity is again available
    to subsequent commands. *)

include module type of Reservation_released_integration_event_t
include module type of Reservation_released_integration_event_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Account.Portfolio.Events.Reservation_released.t

val of_domain : domain -> t
