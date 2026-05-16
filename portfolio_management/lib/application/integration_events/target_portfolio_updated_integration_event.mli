(** Integration event: Portfolio Management updated the target
    portfolio for [book_id].

    Published by {!Set_target_command_workflow} after
    {!Portfolio_management.Target_portfolio.apply_proposal} succeeds.
    [book_id] is the cross-BC partition key — downstream consumers
    (execution / reconciler) filter on it.

    DTO-shaped: primitives + nested view model, no domain values.
    Wire format generated from the atd contract. *)

include module type of Target_portfolio_updated_integration_event_t
include module type of Target_portfolio_updated_integration_event_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Portfolio_management.Target_portfolio.Events.Target_set.t

val of_domain : domain -> t
