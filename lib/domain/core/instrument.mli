(** Composite identity of a tradable instrument: ticker + venue,
    optionally enriched with ISIN and a trading-mode hint (board).

    The four fields capture orthogonal concepts:

    - {!Ticker} — what (issuer-side code, e.g. [SBER])
    - {!Mic}    — where (ISO 10383 venue, e.g. [MISX])
    - {!Isin}   — canonical security ID (ISO 6166), if known
    - {!Board}  — how (trading mode within the venue, e.g. [TQBR]);
                  required by QUIK-family adapters, ignored by Finam

    {!equal} treats two instruments as the same security when they
    share an ISIN+MIC pair (or, when ISIN is absent, Ticker+MIC).
    [board] is *not* part of identity: SBER traded in [TQBR] and
    [SMAL] is the same security with two order books. Routing the
    order to a specific book is the broker's concern. *)

type t = private {
  ticker : Ticker.t;
  venue  : Mic.t;
  isin   : Isin.t option;
  board  : Board.t option;
}

val make :
  ticker:Ticker.t ->
  venue:Mic.t ->
  ?isin:Isin.t ->
  ?board:Board.t ->
  unit -> t

val ticker : t -> Ticker.t
val venue  : t -> Mic.t
val isin   : t -> Isin.t option
val board  : t -> Board.t option

val equal   : t -> t -> bool
val compare : t -> t -> int
val hash    : t -> int
val pp      : Format.formatter -> t -> unit

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
