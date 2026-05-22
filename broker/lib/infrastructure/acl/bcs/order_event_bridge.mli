(** Thin wrapper over {!Websocket.Resilient} for BCS's
    [/orders/execution/ws] channel.

    Unlike the market-data {!Ws_bridge} (one socket per
    [(instrument, timeframe)] subscription), the order WS is
    account-wide: one socket carries every execution event for
    every order the authenticated session can see. Authentication
    is the same Bearer header as REST.

    The bridge is push-only — BCS does not accept subscribe /
    unsubscribe messages on this channel. We just connect, parse
    incoming frames, hand each off as a typed
    {!Ws.Events.Order_event.t}.

    Wired into the broker adapter together with a
    {!Acl_common.Transport_supervisor} so a dropped socket
    transparently re-engages REST polling. *)

val start :
  env:Eio_unix.Stdenv.base ->
  sw:Eio.Switch.t ->
  cfg:Config.t ->
  auth:Auth.t ->
  on_event:(Ws.Events.Order_event.t -> unit) ->
  on_disconnect:(unit -> unit) ->
  on_reconnect:(unit -> unit) ->
  unit
(** Open the WebSocket and spawn the reader / heartbeat fibers
    under [sw]. Raises on initial-connect failure; the caller
    catches and falls back to poll-only operation.

    [on_event] fires for each parsed envelope. Frames that
    fail to parse are logged and dropped.

    [on_disconnect] / [on_reconnect] are forwarded verbatim to
    {!Websocket.Resilient.config} for the supervisor to wire to
    its fallback-poll state machine. *)
