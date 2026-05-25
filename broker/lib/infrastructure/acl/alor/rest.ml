(** Alor Trade REST client.
    Uses a pluggable {!Http_transport.t} so the module is pure and
    testable; production wires in cohttp-eio, tests an in-memory fake.

    Authentication is transparent: the client owns an {!Auth.t} cache
    and resolves a fresh JWT via [Auth.current] right before sending.
    On 401 it refreshes once and retries — covering the race where the
    server expires the JWT slightly before our clock.

    {b Order idempotency.} Alor accepts no caller-supplied order id, so
    a blind transport-level retry of an order POST could double-place.
    Each order POST therefore carries an [X-REQID] header
    ([portfolio;nanos]); Alor deduplicates on it, making the
    [Http_transport] stale-keepalive retry safe. *)

open Core

type t = { transport : Http_transport.t; cfg : Config.t; auth : Auth.t }

let make ~transport ~cfg =
  let auth = Auth.make ~transport ~cfg in
  { transport; cfg; auth }

let url cfg path query : Uri.t =
  let base = cfg.Config.api_base in
  let u = Uri.with_path base (Uri.path base ^ path) in
  Uri.with_query' u query

let ensure_ok (resp : Http_transport.response) : string =
  if resp.status >= 200 && resp.status < 300 then resp.body
  else failwith (Printf.sprintf "Alor REST %d: %s" resp.status resp.body)

let req_with_token ~extra_headers ~meth ~url ~body ~token : Http_transport.request =
  {
    meth;
    url;
    headers =
      [
        ("Authorization", "Bearer " ^ token);
        ("Accept", "application/json");
        ("Content-Type", "application/json");
      ]
      @ extra_headers;
    body;
  }

(** Send carrying the current JWT; on 401 invalidate and retry once
    (shared with {!Finam.Rest} / {!Bcs.Rest} via
    {!Http_transport.with_auth_retry}). *)
let send_with_auth_retry (t : t) ?(extra_headers = []) ~meth ~url ~body () =
  Http_transport.with_auth_retry t.transport
    ~get_token:(fun () -> Auth.current t.auth)
    ~invalidate:(fun () -> Auth.invalidate t.auth)
    ~build_request:(fun ~token -> req_with_token ~extra_headers ~meth ~url ~body ~token)

let get_json t path query : Yojson.Safe.t =
  let resp =
    send_with_auth_retry t ~meth:`GET ~url:(url t.cfg path query) ~body:None ()
  in
  Yojson.Safe.from_string (ensure_ok resp)

(** GET /md/v2/history — historical bars. [tf] is whole seconds for
    intraday frames, a named code ([D]/[W]/[M]) otherwise; [from]/[to]
    are unix seconds. Absent bounds default to the last [n] frames
    ending now, so [bars ~n:500 ~timeframe:H1] yields the last 500
    hourly bars. *)
let bars ?from_ts ?to_ts ?(n = 500) (t : t) ~instrument ~timeframe : Candle.t list =
  let now_ts = Int64.of_float (Unix.gettimeofday ()) in
  let tf_secs = Int64.of_int (Timeframe.to_seconds timeframe) in
  let end_ts = Option.value to_ts ~default:now_ts in
  let start_ts =
    Option.value from_ts ~default:(Int64.sub end_ts (Int64.mul (Int64.of_int n) tf_secs))
  in
  let q =
    [
      ("exchange", Routing.exchange_of t.cfg instrument);
      ("symbol", Routing.symbol_of instrument);
      ("tf", Dto.Wire.timeframe_query timeframe);
      ("from", Int64.to_string start_ts);
      ("to", Int64.to_string end_ts);
      ("format", "Simple");
    ]
    @
    match Routing.instrument_group_of t.cfg instrument with
    | Some g -> [ ("instrumentGroup", g) ]
    | None -> []
  in
  Dto.candles_of_json (get_json t "/md/v2/history" q)

(** Idempotency key for order POSTs: [portfolio;nanos]. Alor dedups on
    it, so the transport's stale-keepalive retry can't double-place. *)
let req_id cfg =
  Printf.sprintf "%s;%Ld" cfg.Config.portfolio
    (Int64.of_float (Unix.gettimeofday () *. 1e9))

let instrument_json cfg (i : Instrument.t) : Yojson.Safe.t =
  let base =
    [
      ("symbol", `String (Routing.symbol_of i));
      ("exchange", `String (Routing.exchange_of cfg i));
    ]
  in
  let group =
    match Routing.instrument_group_of cfg i with
    | Some g -> [ ("instrumentGroup", `String g) ]
    | None -> []
  in
  `Assoc (base @ group)

(** POST /commandapi/warptrans/TRADE/v2/client/orders/actions/market
    (or .../actions/limit).
    [quantity] is the lot count. [comment] is the caller-supplied token
    Alor echoes back on order updates (Alor's only client-side
    correlation handle — there is no separate client-order-id field);
    the adapter stamps the [placement_id] there so a placement stays
    identifiable at the venue even if this call's response is lost.
    Returns Alor's server-assigned [orderNumber]. Stop / stop-limit
    kinds raise (see {!Dto.Wire.kind_to_path}). *)
let place_order
    (t : t)
    ~(instrument : Instrument.t)
    ~(side : Side.t)
    ~(quantity : int)
    ~(kind : Broker_domain.Order.kind)
    ~(tif : Broker_domain.Order.time_in_force)
    ~(comment : string) : string =
  let action = Dto.Wire.kind_to_path kind in
  let path =
    Printf.sprintf "/commandapi/warptrans/TRADE/v2/client/orders/actions/%s" action
  in
  let price_field =
    (* Alor types [price] as a JSON number (OpenAPI [field_PriceCommon]
       is number/decimal), not a decimal-as-string. Match BCS, which
       sends the same MOEX-style body as a float. *)
    match kind with
    | Limit p -> [ ("price", `Float (Decimal.to_float p)) ]
    | _ -> []
  in
  let body =
    `Assoc
      ([
         ("side", `String (Dto.Wire.side_to_wire side));
         ("quantity", `Int quantity);
         ("instrument", instrument_json t.cfg instrument);
         ("user", `Assoc [ ("portfolio", `String t.cfg.portfolio) ]);
         ("timeInForce", `String (Dto.Wire.tif_to_wire tif));
         ("comment", `String comment);
       ]
      @ price_field)
  in
  let resp =
    send_with_auth_retry t
      ~extra_headers:[ ("X-REQID", req_id t.cfg) ]
      ~meth:`POST ~url:(url t.cfg path [])
      ~body:(Some (Yojson.Safe.to_string body))
      ()
  in
  let j = Yojson.Safe.from_string (ensure_ok resp) in
  match Yojson.Safe.Util.member "orderNumber" j with
  | `String s -> s
  | `Int n -> string_of_int n
  | _ -> failwith ("Alor place_order: no orderNumber in " ^ resp.body)

(** DELETE /commandapi/warptrans/TRADE/v2/client/orders/{order_id}.
    [exchange] / [portfolio] / [stop] are required query params. The
    success body is plain text ("success"); a non-2xx (e.g. the order
    already filled → [OrderToCancelNotFound]) raises. *)
let cancel_order t ~exchange ~order_id : unit =
  let path = Printf.sprintf "/commandapi/warptrans/TRADE/v2/client/orders/%s" order_id in
  let q =
    [
      ("portfolio", t.cfg.Config.portfolio);
      ("exchange", exchange);
      ("stop", "false");
      ("format", "Simple");
    ]
  in
  let resp = send_with_auth_retry t ~meth:`DELETE ~url:(url t.cfg path q) ~body:None () in
  ignore (ensure_ok resp)

(** GET /md/v2/Clients/{exchange}/{portfolio}/orders/{order_id}. *)
let get_order t ~exchange ~order_id : Dto.Order.t =
  let path =
    Printf.sprintf "/md/v2/Clients/%s/%s/orders/%s" exchange t.cfg.Config.portfolio
      order_id
  in
  Dto.Order.of_json (get_json t path [ ("format", "Simple") ])

(** GET /md/v2/Clients/{exchange}/{portfolio}/trades — current-session
    executions for the portfolio. Caller filters by parent order id;
    Alor has no per-order trades endpoint that we rely on here. *)
let get_trades t ~exchange : Dto.Trade.t list =
  let path =
    Printf.sprintf "/md/v2/Clients/%s/%s/trades" exchange t.cfg.Config.portfolio
  in
  Dto.Trade.list_of_json (get_json t path [ ("format", "Simple") ])

(** Accessors for {!Ws_bridge} to share auth state and config. *)
let auth t = t.auth

let cfg t = t.cfg
let current_token t = Auth.current t.auth
