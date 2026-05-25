open Core
module Events = Events
module Requests = Requests

type event =
  | Bar of { instrument : Instrument.t; timeframe : Timeframe.t; candle : Candle.t }
  | Trade of Dto.Trade.t

type frame = { guid : string; data : Yojson.Safe.t }

let frame_of_json (j : Yojson.Safe.t) : frame option =
  let open Yojson.Safe.Util in
  match (member "data" j, member "guid" j) with
  | `Null, _ | _, `Null -> None
  | data, `String guid -> Some { guid; data }
  | _ -> None
