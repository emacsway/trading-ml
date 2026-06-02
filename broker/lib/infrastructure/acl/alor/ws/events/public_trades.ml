open Core

type t = Broker_domain.Remote_broker.Events.Public_trade_printed.t

(* The single side-mapping point for Alor (ADR 0032). AllTrades reports
   the aggressor as lowercase "buy"/"sell"; anything else is [None].
   Unlike [Dto.Wire.side_of_wire] (which defaults unknown to Buy, fine
   for our own fills) the public tape must not fabricate a side. *)
let parse_side = function
  | "buy" | "Buy" | "BUY" -> Some Side.Buy
  | "sell" | "Sell" | "SELL" -> Some Side.Sell
  | _ -> None

(* Ticker and venue come from the subscribed instrument (the bridge tracks
   it per guid): Alor's "Simple" AllTrades frame omits [exchange], so
   reconstructing the venue from the body would hit the XXXX placeholder.
   The board, however, IS in the frame, so we graft it on — the identity is
   then the same [SBER@MISX/TQBR] whether or not the caller subscribed with
   the board, matching the BCS adapter (board intrinsic to the instrument,
   not to the subscription form). *)
let instrument_of ~subscribed data =
  let open Yojson.Safe.Util in
  match member "board" data with
  | `String b -> (
      match Board.of_string b with
      | board ->
          Instrument.make
            ~ticker:(Instrument.ticker subscribed)
            ~venue:(Instrument.venue subscribed) ~board ()
      | exception Invalid_argument _ -> subscribed)
  | _ -> subscribed

let parse ~instrument (data : Yojson.Safe.t) : t =
  let open Yojson.Safe.Util in
  let str k =
    match member k data with
    | `String s -> s
    | _ -> ""
  in
  let dec k =
    try Acl_common.Decimal_wire.of_yojson_flex (member k data) with _ -> Decimal.zero
  in
  let ts =
    (* Alor's [timestamp] is Unix MILLISECONDS; our domain timestamp is
       seconds, so divide. (The [time] fallback is already seconds.) Using
       it raw put every bar's open ~56000 years in the future. *)
    match member "timestamp" data with
    | `Int n -> Int64.div (Int64.of_int n) 1000L
    | `Intlit s -> ( try Int64.div (Int64.of_string s) 1000L with _ -> 0L)
    | _ -> (
        match member "time" data with
        | `String s -> Datetime.Iso8601.parse s
        | `Int n -> Int64.of_int n
        | _ -> 0L)
  in
  {
    Broker_domain.Remote_broker.Events.Public_trade_printed.instrument =
      instrument_of ~subscribed:instrument data;
    side = parse_side (str "side");
    quantity = dec "qty";
    price = dec "price";
    ts;
  }
