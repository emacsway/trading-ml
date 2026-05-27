(** Mirror of the order_flow BC's outbound [footprint_completed]
    integration event. Wire shape regenerated from the producer's .atd
    contract, duplicated here per ADR 0001 — no code dependency on
    order_flow. The [clusters] field is present in the wire payload but
    the handler ignores it (the first footprint signal uses only the
    bar-level delta). *)

include module type of Footprint_completed_integration_event_t
include module type of Footprint_completed_integration_event_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
