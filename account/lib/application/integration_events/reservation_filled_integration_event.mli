(** Integration event: a reservation matured into an actual fill.

    Published by {!Commit_fill_command_workflow} after
    {!Account.Portfolio.commit_fill} has settled the reservation.
    Carries the full transactional effect — both the new position
    snapshot and the new cash balance — in one atomic payload so
    consumers cannot observe a transient state that violates
    [equity = cash + Σ qty × mark].

    Subscribed by [pre_trade_risk]'s [Risk_view] (per-instrument
    exposure + cash buffer projection), [execution_management]'s
    [Kill_switch] (peak-equity / drawdown tracker), and the UI
    snapshot layer.

    DTO-shaped: primitives + nested instrument view model, no
    domain values. Decimals on the wire as canonical strings
    (ADR 0007). *)

include module type of Reservation_filled_integration_event_t
include module type of Reservation_filled_integration_event_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Account.Portfolio.Events.Reservation_filled.t

val of_domain : correlation_id:string -> domain -> t
