(** Integration event: the reconciler computed a trade list for
    [book_id]. Published by {!Reconcile_command_workflow}.

    An empty [trades] list is legitimate — it represents "actual
    already matches target", and downstream consumers can treat it
    as a signal of completion.

    DTO-shaped: primitives + nested view model. *)

include module type of Trade_intents_planned_integration_event_t
include module type of Trade_intents_planned_integration_event_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Portfolio_management.Reconciliation.Events.Trades_planned.t

val of_domain : domain -> t
