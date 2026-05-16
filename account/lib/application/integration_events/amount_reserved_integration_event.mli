(** Integration event: Account reserved cash / quantity for a
    pending order.

    Published by {!Reserve_command_workflow} after
    {!Account.Portfolio.try_reserve} succeeds. [reservation_id]
    is the cross-BC saga key — the inbound HTTP adapter propagates
    it into {!Submit_order_command.t} so Broker echoes it back, and
    the Account compensation subscriber matches by it on rejection.

    DTO-shaped: primitives + nested view model, no domain values.
    Wire format generated from the atd contract. *)

include module type of Amount_reserved_integration_event_t
include module type of Amount_reserved_integration_event_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Account.Portfolio.Events.Amount_reserved.t

val of_domain : correlation_id:string -> domain -> t
