(** Inbound command to the pre_trade_risk BC: "absorb a fill
    reported by Account."

    Driven by the inbound ACL handler subscribing to
    [in-memory://account.reservation-filled]. Carries the full
    transactional effect — both the new cash balance and the new
    position snapshot — in one atomic payload, so [Risk_view]
    advances atomically without exposing a transient state that
    violates [equity = cash + Σ qty × mark].

    The wire shape is generated from
    [shared/contracts/pre_trade_risk/commands/record_fill_command.atd]
    via atdgen. *)

include module type of Record_fill_command_t

include module type of Record_fill_command_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
