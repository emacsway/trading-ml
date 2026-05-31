open Core

type t = Broker_domain.Remote_broker.Events.Public_trade_printed.t

let num_field k j =
  let open Yojson.Safe.Util in
  match member k j with
  | `Float f -> Decimal.of_float f
  | `Int n -> Decimal.of_int n
  | `String s -> Decimal.of_string s
  | `Intlit s -> Decimal.of_string s
  | _ -> Decimal.zero

(* The single side-mapping point for BCS (ADR 0032). BCS reports the
   public-tape aggressor as "BUY"/"SELL"; anything else (or absent) is
   [None]. Flip here if it ever proves to mark the resting side. *)
let parse_side : Yojson.Safe.t -> Side.t option = function
  | `String ("BUY" | "buy" | "Buy") -> Some Side.Buy
  | `String ("SELL" | "sell" | "Sell") -> Some Side.Sell
  | _ -> None

let instrument_from ~ticker ~class_code =
  Instrument.make ~ticker:(Ticker.of_string ticker) ~venue:(Mic.of_string "MISX")
    ~board:(Board.of_string class_code) ()

let parse (j : Yojson.Safe.t) : t =
  let open Yojson.Safe.Util in
  let ticker = member "ticker" j |> to_string in
  let class_code = member "classCode" j |> to_string in
  let instrument = instrument_from ~ticker ~class_code in
  let ts =
    match member "dateTime" j with
    | `String s -> Datetime.Iso8601.parse s
    | _ -> 0L
  in
  {
    Broker_domain.Remote_broker.Events.Public_trade_printed.instrument;
    side = parse_side (member "side" j);
    quantity = num_field "quantity" j;
    price = num_field "price" j;
    ts;
  }
