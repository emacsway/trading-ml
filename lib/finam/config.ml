(** Endpoint configuration for Finam Trade API.

    Authentication is a two-step flow (see Finam's getting-started docs):
      1. The user holds a long-lived [secret] issued on the portal.
      2. [POST /v1/sessions] with that secret returns a short-lived JWT.
      3. The JWT goes into [Authorization: Bearer] on every other call.
    [Finam.Auth] hides this behind a cache; consumers work with the JWT
    transparently. *)

type t = {
  rest_base : Uri.t;
  ws_url : Uri.t;
  secret : string;
  account_id : string option;
}

(* [trade-api.finam.ru] (с дефисом) возвращает 301 → [tradeapi.finam.ru].
   WebSocket-хост — пока гипотеза, подтвердится при активации WS. *)
let make
    ?(rest_base = Uri.of_string "https://tradeapi.finam.ru")
    ?(ws_url = Uri.of_string "wss://tradeapi.finam.ru/")
    ?account_id
    ~secret
    () =
  { rest_base; ws_url; secret; account_id }
