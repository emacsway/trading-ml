(** Endpoint configuration for Finam Trade API.
    Defaults match the published production hosts as of the API docs:
    - REST: https://trade-api.finam.ru   (legacy)
    - gRPC/new: api.finam.ru:443
    - WebSocket (async-api): wss://ws-api.finam.ru/trade-api/ *)

type t = {
  rest_base : Uri.t;
  ws_url : Uri.t;
  access_token : string;
  account_id : string option;
}

let make
    ?(rest_base = Uri.of_string "https://trade-api.finam.ru")
    ?(ws_url = Uri.of_string "wss://ws-api.finam.ru/trade-api/")
    ?account_id
    ~access_token
    () =
  { rest_base; ws_url; access_token; account_id }
