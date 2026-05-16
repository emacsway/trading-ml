(** Read-model DTO for {!Broker_domain.Order.t}.

    The wire shape is generated from
    [shared/contracts/broker/view_models/order_view_model.atd]
    via atdgen; the embedded [instrument_view_model] and
    [order_kind_view_model] fields cross-reference their respective
    .atd files in the same library, sharing the typed record
    across producers and consumers within [broker_view_models]. *)

include module type of Order_view_model_t

include module type of Order_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Broker_domain.Order.t

val of_domain : domain -> t
