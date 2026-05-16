(** Wire-shape projection of an order's observable state.

    Identity in this projection is [placement_id] (the cross-BC
    saga key). Venue-native handles ([client_order_id],
    server-side ids, exec ids) are private to each ACL adapter
    and do not appear here.

    The wire shape is generated from
    [shared/contracts/broker/view_models/order_view_model.atd]
    via atdgen; the embedded [instrument_view_model] and
    [order_kind_view_model] fields cross-reference their
    respective .atd files in the same library, sharing the typed
    record across producers and consumers within
    [broker_view_models]. *)

include module type of Order_view_model_t
include module type of Order_view_model_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

val of_domain : placement_id:int -> Order.t -> t
(** Project broker's ACL-internal intermediate {!Order.t} onto
    the wire view model. [placement_id] is threaded from the
    caller (the saga key), since the intermediate has no notion
    of it — it only carries the venue-side identity, which the
    projection drops. *)
