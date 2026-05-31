(** Inbound Alor public-tape ([AllTradesGetAndSubscribe]) frame parser.

    One executed tape print -> {!Public_trade_printed}, the
    venue's all-participants flow (distinct from the personal
    [TradesGetAndSubscribeV2] fills). Instrument from symbol/exchange/
    board; [side] is the aggressor ("buy"/"sell", else [None]). *)

type t = Broker_domain.Remote_broker.Events.Public_trade_printed.t

val parse : Yojson.Safe.t -> t
