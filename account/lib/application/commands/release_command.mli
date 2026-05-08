(** Inbound command to the Account BC: "release a previously
    earmarked reservation."

    Sent by the compensation choreography subscriber when Broker
    publishes {!Order_rejected.t} / {!Order_unreachable.t} carrying
    the matching [reservation_id]. The originating reservation was
    created by {!Reserve_command.t} on the same id.

    [correlation_id] propagates the saga-instance identifier from
    the {!Place_order_pm} Process Manager so audit / SSE can
    attribute the compensating release back to the originating
    saga; it is not consumed by the Account aggregate itself. *)

type t = { correlation_id : string; reservation_id : int } [@@deriving yojson]
