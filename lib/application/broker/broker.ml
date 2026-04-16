(** Broker abstraction — everything the server / engine need from a
    market data & execution provider, expressed in domain types only.
    Concrete integrations (Finam, BCS, …) implement [S] in their own
    library; the server talks to them through an existential [client]
    wrapper so adding a new broker is a new module, not a new branch
    in every switch. *)

open Core

module type S = sig
  type t

  val name : string
  (** Identifier used on the CLI (e.g. "finam", "bcs") and in logs. *)

  val bars :
    t ->
    n:int ->
    instrument:Instrument.t ->
    timeframe:Timeframe.t ->
    Candle.t list
  (** Fetch the last [n] bars for [instrument] at [timeframe]. The
      adapter routes the request using whatever fields it needs:
      Finam takes [(ticker, mic)]; BCS takes [(ticker, board)] and
      ignores [mic]; both honor [board] when present (Finam falls
      back to its server-side primary-board choice when absent). *)

  val venues : t -> Mic.t list
  (** Venues this broker can route to, as ISO-10383 MIC codes.
      Human-readable labels are not the broker's responsibility — the
      UI maps known MICs to display names; unknown MICs render as the
      raw code. *)
end

type client = E : (module S with type t = 't) * 't -> client

let make (type a) (module M : S with type t = a) (x : a) : client =
  E ((module M), x)

let name (E ((module M), _)) = M.name

let bars (E ((module M), t)) ~n ~instrument ~timeframe =
  M.bars t ~n ~instrument ~timeframe

let venues (E ((module M), t)) = M.venues t
