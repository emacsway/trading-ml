let parse (data : Yojson.Safe.t) : Dto.Trade.t = Dto.Trade.of_json data

let to_domain ~(placement_id : int) (dt : Dto.Trade.t) :
    Broker_domain.Remote_broker.Events.Trade_executed.t =
  {
    placement_id;
    trade_id = dt.trade.trade_id;
    instrument = dt.instrument;
    side = dt.side;
    quantity = dt.trade.quantity;
    price = dt.trade.price;
    fee = dt.trade.fee;
    ts = dt.trade.ts;
  }
