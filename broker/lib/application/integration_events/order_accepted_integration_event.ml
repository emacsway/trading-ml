type t = {
  correlation_id : string;
  reservation_id : int;
  broker_order : Broker_queries.Order_view_model.t;
}
[@@deriving yojson]
