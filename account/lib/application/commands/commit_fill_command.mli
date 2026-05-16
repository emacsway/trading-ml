(** Inbound command to the Account BC: "commit the reservation
    that was earmarked under [reservation_id] using the broker's
    actual fill numbers."

    Triggered by an inbound
    {!Account_external_integration_events.Order_filled_integration_event.t}
    arriving on the [in-memory://broker.order-filled] topic, which
    the saga-driven paper / real broker emits when a venue (or the
    matching simulator) reports a fill. The handler updates
    {!Account.Portfolio.t} via {!Account.Portfolio.commit_fill}
    and the workflow publishes
    {!Account_integration_events.Position_changed_integration_event}
    and {!Account_integration_events.Cash_changed_integration_event}.

    Wire-format DTO — primitives only. Decimals as canonical
    strings (ADR 0007). The wire shape is generated from
    [shared/contracts/account/commands/commit_fill_command.atd]
    via atdgen. *)

include module type of Commit_fill_command_t

include module type of Commit_fill_command_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
