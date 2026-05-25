open Core

type t = {
  order_id : string;
  instrument : Instrument.t;
  side : Side.t;
  quantity : Decimal.t;
  filled : Decimal.t;
  kind : Broker_domain.Order.kind;
  tif : Broker_domain.Order.time_in_force;
  status : Broker_domain.Order.status;
  placed_ts : int64;
}

let to_domain ~placement_id (v : t) : Broker_domain.Order.t =
  {
    placement_id;
    instrument = v.instrument;
    side = v.side;
    quantity = v.quantity;
    filled = v.filled;
    kind = v.kind;
    tif = v.tif;
    status = v.status;
    placed_ts = v.placed_ts;
  }

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
  let instrument = Wire.instrument_of_json j in
  let side = Wire.side_of_wire (str "side") in
  (* Lots throughout: [qtyBatch] ordered, [filledQtyBatch] executed —
     the explicit lot fields, not the ambiguous legacy [qty]. *)
  let quantity = dec "qtyBatch" in
  let filled = dec "filledQtyBatch" in
  let price =
    match member "price" j with
    | `Null -> None
    | p -> Some (Acl_common.Decimal_wire.of_yojson_flex p)
  in
  let kind = Wire.kind_of_wire (str "type") ~price in
  let tif = Wire.tif_of_wire (str "timeInForce") in
  let status = Wire.status_of_wire (str "status") ~filled ~quantity in
  let placed_ts =
    match member "transTime" j with
    | `String s -> Datetime.Iso8601.parse s
    | _ -> 0L
  in
  {
    order_id = str "id";
    instrument;
    side;
    quantity;
    filled;
    kind;
    tif;
    status;
    placed_ts;
  }
