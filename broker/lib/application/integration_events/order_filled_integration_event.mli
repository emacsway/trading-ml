(** Integration event: a fill (or partial fill) was observed at
    the venue against an order this broker adapter placed.
    Published on [in-memory://broker.order-filled] by the live
    adapter when its WebSocket subscription delivers a trade
    update; consumed by [execution_management] for the saga's
    commit-fill leg.

    Identity: the saga key is [placement_id : int], which the
    adapter recovers from the venue-side [order_id] via its
    private placement map. [correlation_id] is recovered from
    the broker's command-log keyed on that [placement_id] so the
    outbound IE carries the originating Submit saga even though
    the WS event itself arrives outside command-in-scope.

    Paper-broker BC emits its own variant of this same wire
    contract (`Paper_broker_integration_events.Order_filled_integration_event`)
    for paper-mode runs. Both live publishers and the
    paper-broker simulator target the same URI on the bus, so
    the EM consumer is source-agnostic. *)

include module type of Order_filled_integration_event_t
include module type of Order_filled_integration_event_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
