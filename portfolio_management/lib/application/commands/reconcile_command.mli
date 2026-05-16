(** Inbound command to PM: "compute the trade list bringing
    [book_id]'s actual_portfolio to its target_portfolio and announce
    it via the {!Trade_intents_planned_integration_event.t}."

    Idempotent — called whenever target or actual changes (or
    explicitly by a tick / scheduler). [computed_at] supplies the
    timestamp the produced domain event will carry.

    The wire shape is generated from
    [shared/contracts/portfolio_management/commands/reconcile_command.atd]
    via atdgen. *)

include module type of Reconcile_command_t

include module type of Reconcile_command_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
