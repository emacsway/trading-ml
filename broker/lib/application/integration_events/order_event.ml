type t =
  | Order_accepted of {
      client_order_id : string;
      broker_order : Queries.Order_view_model.t;
    }
  | Order_rejected of { client_order_id : string; reason : string }
  | Order_unreachable of { client_order_id : string; reason : string }
[@@deriving yojson]

let client_order_id_of = function
  | Order_accepted { client_order_id; _ }
  | Order_rejected { client_order_id; _ }
  | Order_unreachable { client_order_id; _ } ->
      client_order_id
