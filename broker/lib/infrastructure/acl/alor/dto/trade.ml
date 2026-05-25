open Core

type t = {
  order_id : string;
  instrument : Instrument.t;
  side : Side.t;
  trade : Broker_domain.Order.Trade.t;
}

(** Decode one Alor trade object. Shared by the REST [/trades] list and
    the WS [TradesGetAndSubscribeV2] frame; both use the Simple format,
    which names the trade id [id] and the parent order id [orderno]
    (the [orderNo] casing only appears in the V2/Heavy formats — kept
    as a fallback). [commission] is nullable on the wire (null on the
    derivatives market) and defaults to zero.

    Quantity is read from the explicit lot field [qtyBatch], not the
    ambiguous legacy [qty]: the adapter submits in lots and the
    consuming OrderTicket reconciles fills against that lot-denominated
    ordered quantity. (Alor also ships [qtyUnits] in shares, with
    [price] per unit — see ADR 0030 on the lots/units gap.) *)
let of_json (j : Yojson.Safe.t) : t =
  let open Yojson.Safe.Util in
  let str k =
    match member k j with
    | `String s -> s
    | _ -> ""
  in
  let dec k =
    try Acl_common.Decimal_wire.of_yojson_flex (member k j) with _ -> Decimal.zero
  in
  let order_id =
    match str "orderno" with
    | "" -> str "orderNo"
    | s -> s
  in
  let ts =
    match member "date" j with
    | `String s -> Datetime.Iso8601.parse s
    | _ -> 0L
  in
  {
    order_id;
    instrument = Wire.instrument_of_json j;
    side = Wire.side_of_wire (str "side");
    trade =
      {
        trade_id = str "id";
        ts;
        quantity = dec "qtyBatch";
        price = dec "price";
        fee = dec "commission";
      };
  }

let list_of_json (j : Yojson.Safe.t) : t list =
  match j with
  | `List items -> List.map of_json items
  | _ -> []
