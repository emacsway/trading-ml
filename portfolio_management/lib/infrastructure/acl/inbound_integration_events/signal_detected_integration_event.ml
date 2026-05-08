type t = {
  strategy_id : string;
  instrument : Portfolio_management_inbound_queries.Instrument_view_model.t;
  direction : string;
  strength : float;
  price : string;
  reason : string;
  occurred_at : string;
}
[@@deriving yojson]
