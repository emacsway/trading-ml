(** Inbound command to the Portfolio Management BC: "commit a fill
    into the [actual_portfolio] model."

    Triggered by an inbound [Reservation_filled_integration_event]
    from the Account BC carrying the full transactional effect — new
    cash balance, new per-instrument position and VWAP — in one
    atomic payload. PM commits them together so consumers never
    observe a transient state that violates
    [equity = cash + Σ qty × mark].

    The wire shape is generated from
    [shared/contracts/portfolio_management/commands/commit_actual_fill_command.atd]
    via atdgen. *)

include module type of Commit_actual_fill_command_t

include module type of Commit_actual_fill_command_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
