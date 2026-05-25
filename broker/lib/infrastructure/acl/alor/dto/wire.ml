(** Alor wire-format enum and timeframe codecs. Isolates the
    venue's literal strings so a protocol change touches one file.

    Alor's enums are deliberately narrow (see the alor.dev OpenAPI):
    side is [buy|sell], order status is only [working|filled|canceled
    |rejected] (note American single-l [canceled]), order type is
    [limit|market]. There is no dedicated "partially filled" status —
    a partially-executed order stays [working] with a non-zero
    [filledQtyBatch], so {!status_of_wire} derives [Partially_filled]
    from the filled/quantity split rather than from a wire token. *)

open Core

(* ---- Side ---- *)

let side_to_wire : Side.t -> string = function
  | Buy -> "buy"
  | Sell -> "sell"

let side_of_wire : string -> Side.t = function
  | "sell" -> Sell
  | _ -> Buy

(* ---- Order type ---- *)

let kind_to_path : Broker_domain.Order.kind -> string = function
  | Market -> "market"
  | Limit _ -> "limit"
  | Stop _ | Stop_limit _ ->
      (* Alor exposes dedicated stop / stop-limit endpoints with a
         distinct condition/triggerPrice body; routing the domain
         stop kinds there is deferred (see {!Rest.place_order}). *)
      failwith "alor: stop / stop-limit orders are not yet supported"

let kind_of_wire (type_ : string) ~(price : Decimal.t option) : Broker_domain.Order.kind =
  match (type_, price) with
  | "limit", Some p -> Limit p
  | "limit", None -> Limit Decimal.zero
  | _ -> Market

(* ---- Time in force ---- *)

let tif_to_wire : Broker_domain.Order.time_in_force -> string = function
  | GTC -> "goodtillcancelled"
  | DAY -> "oneday"
  | IOC -> "immediateorcancel"
  | FOK -> "fillorkill"

let tif_of_wire : string -> Broker_domain.Order.time_in_force = function
  | "goodtillcancelled" -> GTC
  | "immediateorcancel" -> IOC
  | "fillorkill" -> FOK
  | _ -> DAY

(* ---- Status ---- *)

(** Project Alor's [status] onto the broker domain status. [working]
    splits into [New] / [Partially_filled] / [Filled] by the
    filled/quantity relation, since Alor has no partial-fill token. *)
let status_of_wire (status : string) ~(filled : Decimal.t) ~(quantity : Decimal.t) :
    Broker_domain.Order.status =
  match status with
  | "filled" -> Filled
  | "canceled" -> Cancelled
  | "rejected" -> Rejected
  | "working" | _ ->
      if Decimal.is_zero filled then New
      else if Decimal.compare filled quantity >= 0 then Filled
      else Partially_filled

(* ---- Timeframe ---- *)

(** Alor encodes intraday timeframes as a whole-second count and the
    coarser ones as named codes ([D] day, [W] week, [M] month). Note
    the monthly code is ["M"], not the model's [MN1] token. *)
let timeframe_secs : Timeframe.t -> int option = function
  | M1 -> Some 60
  | M5 -> Some 300
  | M15 -> Some 900
  | M30 -> Some 1800
  | H1 -> Some 3600
  | H4 -> Some 14400
  | D1 | W1 | MN1 -> None

let timeframe_named : Timeframe.t -> string = function
  | D1 -> "D"
  | W1 -> "W"
  | MN1 -> "M"
  | M1 | M5 | M15 | M30 | H1 | H4 -> ""

(** Wire form for [tf] — always a string, whether the REST query
    parameter or the WS subscribe field (Alor types [tf] as a string
    that is either a second count, ["60"], or a named code, ["D"]). *)
let timeframe_query (tf : Timeframe.t) : string =
  match timeframe_secs tf with
  | Some s -> string_of_int s
  | None -> timeframe_named tf

(* ---- Instrument ---- *)

(** Rebuild an {!Instrument.t} from a wire object carrying [symbol] /
    [board] / [exchange] (shared by the order and trade DTOs). A bad
    board is dropped rather than failing the whole decode — the
    instrument stays routable without it. *)
let instrument_of_json (j : Yojson.Safe.t) : Instrument.t =
  let open Yojson.Safe.Util in
  let str k =
    match member k j with
    | `String s -> s
    | _ -> ""
  in
  let ticker = Ticker.of_string (str "symbol") in
  let venue = Routing.mic_of_exchange (str "exchange") in
  let board =
    match member "board" j with
    | `String "" | `Null -> None
    | `String s -> ( try Some (Board.of_string s) with Invalid_argument _ -> None)
    | _ -> None
  in
  Instrument.make ~ticker ~venue ?board ()
