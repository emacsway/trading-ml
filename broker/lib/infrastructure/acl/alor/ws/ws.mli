(** Alor WebSocket ([wss://api.alor.ru/ws]): one multiplexed socket
    carries every subscription. Outbound, the client opens a stream
    with an opcode envelope ([BarsGetAndSubscribe],
    [TradesGetAndSubscribeV2], ...) carrying a client-chosen [guid] and
    the JWT in a [token] field. Inbound, every data frame is
    [{ "data": <payload>, "guid": "<same-guid>" }] — there is no
    opcode on the response, so correlation is purely by [guid].

    Because a bar payload carries no instrument/timeframe of its own,
    the [(instrument, timeframe)] context is recovered from the [guid]
    by {!Ws_bridge}'s registry; this module owns only the channel-
    agnostic frame split and the request encoders. *)

open Core

module Events = Events
(** Per-channel inbound frame decoders + domain projections. *)

module Requests = Requests
(** Channel subscribe / unsubscribe encoders (outbound). *)

(** A resolved inbound event. The bar variant is enriched by the
    bridge with the [(instrument, timeframe)] looked up from the
    frame's [guid]; the trade variant carries the parsed wire DTO
    (its parent order id resolves to a [placement_id] in the broker). *)
type event =
  | Bar of { instrument : Instrument.t; timeframe : Timeframe.t; candle : Candle.t }
  | Trade of Dto.Trade.t
  | Public_trades of Events.Public_trades.t
      (** A public-tape print (AllTradesGetAndSubscribe) — the
          all-participants flow, distinct from the personal [Trade]. *)

type frame = { guid : string; data : Yojson.Safe.t }
(** The channel-agnostic shape of an Alor data frame. *)

val frame_of_json : Yojson.Safe.t -> frame option
(** [Some] when the envelope is a data frame (both [data] and [guid]
    present); [None] for subscribe confirmations / control frames
    (which carry [requestGuid] / [httpCode] / [message] instead).
    Never raises. *)
