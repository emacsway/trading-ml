(** Read-model DTO for {!Core.Instrument.t}.

    Primitive-typed: the four identity fields projected as plain
    strings. Carries no domain invariants — this is an outbound
    projection only; reconstructing a valid {!Core.Instrument.t}
    from a DTO is the concern of the future [commands/] layer. *)

include module type of Instrument_view_model_t
include module type of Instrument_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Core.Instrument.t

val of_domain : domain -> t
