(** Wire-format projection of {!Paper_broker.Order.Values.Order_kind.t}.

    Cross-BC traffic on the [broker.submit-order-command] command
    channel carries [kind] as this discriminated record (a string
    [type] plus optional price fields). ACL adapters on the receiving
    end parse it back into the strongly-typed domain VO.

    The wire shape is generated from
    [shared/contracts/paper_broker/view_models/order_kind_view_model.atd]
    via atdgen. *)

include module type of Order_kind_view_model_t

include module type of Order_kind_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Paper_broker.Order.Values.Order_kind.t

val of_domain : domain -> t
(** Lossless projection: every domain variant maps to exactly one
    wire shape. Missing-field validity is the inverse parser's
    concern. *)
