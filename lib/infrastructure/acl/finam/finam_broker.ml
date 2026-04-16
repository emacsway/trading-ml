(** Adapter: exposes [Finam.Rest.t] through the broker-agnostic
    [Broker.S] interface. All Finam-specific translation lives here so
    callers (server, CLI, tests) program against [Broker.client]. *)

open Core

type t = Rest.t

let name = "finam"

let bars t ~n ~instrument ~timeframe =
  Rest.bars t ~n ~instrument ~timeframe

(** Decode Finam's [/v1/exchanges] payload into MIC codes. We drop the
    [name] field — display labels are the UI's concern, not the
    adapter's. Any malformed MIC is silently filtered (Finam has shipped
    placeholder rows in the past). *)
let venues t : Mic.t list =
  let j = Rest.exchanges t in
  match Yojson.Safe.Util.member "exchanges" j with
  | `List items ->
    List.filter_map (fun item ->
      match Yojson.Safe.Util.member "mic" item with
      | `String m -> (try Some (Mic.of_string m) with Invalid_argument _ -> None)
      | _ -> None
    ) items
  | _ -> []

let as_broker (rest : Rest.t) : Broker.client =
  Broker.make (module struct
    type nonrec t = t
    let name = name
    let bars = bars
    let venues = venues
  end) rest
