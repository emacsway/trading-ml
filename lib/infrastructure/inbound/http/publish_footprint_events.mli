(** SSE publisher for sealed footprints.

    The composition root subscribes this to
    [in-memory://order-flow.footprint-completed]; each event is fanned to
    the [footprint] SSE channel, keyed by [(qualified symbol, boundary
    token)] so only subscribers that declared interest in that feed
    receive it. The on-wire payload is the event's own DTO — the same
    shape [GET /api/footprints] returns. *)

module Footprint_completed =
  Order_flow_integration_events.Footprint_completed_integration_event

val handle : registry:Stream.t -> Footprint_completed.t -> unit
