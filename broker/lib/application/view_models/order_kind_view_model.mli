(** Read-model DTO for {!Broker_domain.Order.kind}.

    Flattened discriminated union: [type_] is the tag
    ([MARKET] / [LIMIT] / [STOP] / [STOP_LIMIT]) and the
    kind-specific price fields are optional — present only for
    the kinds that need them.

    The wire shape is generated from
    [shared/contracts/broker/view_models/order_kind_view_model.atd]
    via atdgen. *)

include module type of Order_kind_view_model_t

include module type of Order_kind_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Broker_domain.Order.kind

val of_domain : domain -> t
