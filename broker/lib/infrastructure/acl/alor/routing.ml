(** Instrument → Alor wire-routing helpers.

    Alor addresses an instrument by a [(symbol, exchange, instrumentGroup)]
    triple rather than the [TICKER@MIC] form our model uses:
    - [symbol]          — the bare ticker (Alor's [code] on WS, [symbol]
                          in REST/order bodies);
    - [exchange]        — Alor venue code (["MOEX"] | ["SPBX"]), derived
                          from the instrument's ISO-10383 MIC;
    - [instrumentGroup] — the board (e.g. ["TQBR"]), taken from the
                          instrument's [board] or the config default. *)

open Core

let symbol_of (i : Instrument.t) : string = Ticker.to_string (Instrument.ticker i)

(** Map an ISO-10383 MIC onto Alor's venue code. MOEX sections
    ([MISX] equities, [RTSX]/[XMOS] derivatives) collapse to ["MOEX"];
    SPB Exchange ([XSPB]/[SPBE]/[IEXG]) to ["SPBX"]. Anything else
    falls back to the configured [default_exchange] so an unmapped MIC
    degrades to the operator's primary venue rather than failing. *)
let exchange_of (cfg : Config.t) (i : Instrument.t) : string =
  match Mic.to_string (Instrument.venue i) with
  | "MISX" | "RTSX" | "XMOS" -> "MOEX"
  | "XSPB" | "SPBE" | "IEXG" -> "SPBX"
  | _ -> cfg.Config.default_exchange

(** Board for the [instrumentGroup] field: the instrument's own board
    wins; otherwise the config default ([None] lets Alor choose the
    primary board). *)
let instrument_group_of (cfg : Config.t) (i : Instrument.t) : string option =
  match Instrument.board i with
  | Some b -> Some (Board.to_string b)
  | None -> cfg.Config.default_board

(** Reverse of {!exchange_of}: map an Alor venue code back onto a MIC
    when rebuilding an {!Instrument.t} from an order/trade object that
    carries [exchange] rather than a MIC. ["MOEX"] → [MISX] (equities,
    our default section), ["SPBX"] → [XSPB]. Unknown codes yield the
    placeholder [XXXX] (still a valid 4-char MIC), so a decode never
    fails on an unexpected venue. *)
let mic_of_exchange : string -> Mic.t = function
  | "MOEX" -> Mic.of_string "MISX"
  | "SPBX" -> Mic.of_string "XSPB"
  | _ -> Mic.of_string "XXXX"
