(** Alor wire representation of an order, decoded from the
    [GET /md/v2/Clients/{exchange}/{portfolio}/orders/{orderId}]
    response (Simple format). Distinct from the broker domain
    {!Broker_domain.Order.t}: it carries the venue-side [order_id]
    that never crosses the ACL boundary. *)

type t = {
  order_id : string;
      (** Alor's server-assigned order id (the [id] field; equal to
          the [orderNumber] returned at placement). The adapter's
          only venue handle; dropped by {!to_domain}. *)
  instrument : Core.Instrument.t;
  side : Core.Side.t;
  quantity : Decimal.t;  (** Ordered quantity in lots (Alor [qty]). *)
  filled : Decimal.t;  (** Executed quantity in lots ([filledQtyBatch]). *)
  kind : Broker_domain.Order.kind;
  tif : Broker_domain.Order.time_in_force;
  status : Broker_domain.Order.status;
  placed_ts : int64;  (** [transTime] normalised to int64 epoch. *)
}

val of_json : Yojson.Safe.t -> t
val to_domain : placement_id:int -> t -> Broker_domain.Order.t
