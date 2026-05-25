(** Alor wire representation of one executed trade, decoded from a
    [/md/v2/Clients/{exchange}/{portfolio}/trades] element or a WS
    [TradesGetAndSubscribeV2] frame. [order_id] is the parent order's
    id, kept so the adapter can correlate a fill back to its placement;
    [trade] is the boundary-crossing child entity. *)

type t = {
  order_id : string;
      (** Parent order id — Alor [orderno] (REST) / [orderNo] (WS V2).
          Used only inside the adapter to resolve [placement_id]. *)
  instrument : Core.Instrument.t;
  side : Core.Side.t;
  trade : Broker_domain.Order.Trade.t;
      (** [{ trade_id; ts; quantity; price; fee }] — quantity in lots
          ([qty]), [fee] from [commission] (zero when Alor reports
          null, e.g. on the derivatives market). *)
}

val of_json : Yojson.Safe.t -> t
val list_of_json : Yojson.Safe.t -> t list
