(** Read-model DTO for {!Core.Instrument.t}. Generated wire shape
    from [shared/contracts/execution_management/view_models/instrument_view_model.atd]. *)

include module type of Instrument_view_model_t

include module type of Instrument_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

val of_domain : Core.Instrument.t -> t
