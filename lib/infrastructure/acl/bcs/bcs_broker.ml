(** Adapter from [Bcs.Rest.t] to [Broker.S]. Symmetric to
    [Finam_broker]: returns the venues this broker can route to as MIC
    codes. BCS-via-QUIK is MOEX-only in our setup, so this is a single
    static MIC; the per-board distinction (TQBR/SPBFUT/...) lives on
    the {!Instrument.t} as [board], not here. *)

open Core

type t = Rest.t

let name = "bcs"

let bars t ~n ~instrument ~timeframe =
  Rest.bars t ~n ~instrument ~timeframe

let venues _t : Mic.t list = [ Mic.of_string "MISX" ]

let as_broker (rest : Rest.t) : Broker.client =
  Broker.make (module struct
    type nonrec t = t
    let name = name
    let bars = bars
    let venues = venues
  end) rest
