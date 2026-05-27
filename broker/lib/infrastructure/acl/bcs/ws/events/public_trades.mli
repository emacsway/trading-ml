(** Inbound BCS public-trade (all-trades, [dataType:2]) frame parser.

    One executed tape print -> {!Remote_public_trade_updated}, the
    venue's all-participants flow (distinct from the personal
    execution-status channel). Instrument is rebuilt from ticker +
    classCode; [side] is the aggressor (BUY/SELL, else [None]). *)

type t = Broker_domain.Remote_broker.Events.Remote_public_trade_updated.t

val parse : Yojson.Safe.t -> t
