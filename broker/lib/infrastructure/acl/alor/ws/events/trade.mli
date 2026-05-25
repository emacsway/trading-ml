(** Inbound WS fill frame ([TradesGetAndSubscribeV2]). The data payload
    shares its shape with the REST [/trades] element, so parsing reuses
    {!Dto.Trade.of_json}; this module adds the recognizer projection
    into the domain fill event (per Vernon's "external system as a
    source of Domain Events"). The parent order id → [placement_id]
    resolution stays in the adapter, which owns the placement store. *)

val parse : Yojson.Safe.t -> Dto.Trade.t
(** Decode a fill frame's [data] object into the wire trade DTO. *)

val to_domain :
  placement_id:int -> Dto.Trade.t -> Broker_domain.Remote_broker.Events.Trade_executed.t
(** Project the wire trade onto the domain fill event, stamping the
    resolved [placement_id]. Pure — the caller supplies [placement_id]
    after resolving the trade's parent order id through the adapter's
    placement store. *)
