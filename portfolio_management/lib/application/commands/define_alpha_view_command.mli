(** Inbound command to PM: «record current alpha view for
    [(alpha_source_id, instrument)] as the supplied directional
    reading».

    Wire-format DTO — primitives only. The handler parses each field
    into PM-domain types and invokes
    {!Portfolio_management.Alpha_view.define} on the matching
    aggregate (auto-creating one via {!Alpha_view.empty} on first
    sighting).

    Triggered by:
    - PM-side ACL adapter that translates strategy's
      {!Strategy_integration_events.Signal_detected_integration_event.t}
      into this command after resolving [strategy_id → alpha_source_id];
    - external CLI / future REST override.

    [book_id] is deliberately absent: it is not part of [Alpha_view]'s
    identity. Per-book fan-out happens later, in the
    {!Apply_proposed_targets_on_alpha_direction_changed} domain-
    event handler.

    The wire shape is generated from
    [shared/contracts/portfolio_management/commands/define_alpha_view_command.atd]
    via atdgen. *)

include module type of Define_alpha_view_command_t

include module type of Define_alpha_view_command_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
