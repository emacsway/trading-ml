# 0030. Alor broker ACL adapter

**Status**: Accepted
**Date**: 2026-05-25

## Context

Alor (alor.dev) is a third Russian venue we want to route to,
alongside Finam and BCS. The broker domain model (ADR 0015) already
fixes the contract: every venue is reached through the `Broker.S`
port, speaks the BC's uniform `Order` vocabulary, and confines all
protocol specifics below the ACL boundary. Adding Alor is therefore a
new adapter under `broker/lib/infrastructure/acl/alor/`, not a change
to any shared type.

Alor's wire protocol differs from both existing templates in three
ways that shape the adapter. They are worth recording because each is
a deliberate departure from the Finam/BCS shape an implementer would
otherwise copy.

## Decision

Implement `Alor.*` mirroring the Finam adapter's module layout (config,
auth, rest, routing, ws_bridge, placement_handle_store, dto/, ws/,
alor_broker) and reusing the shared `Acl_common.Transport_supervisor` /
`Stream_dedup` and `Websocket.Resilient` machinery. The factory gains
`Opened.open_alor`; the runtime config gains an `Alor` broker variant
(`portfolio` + refresh-token + optional `exchange`).

Three Alor-specific points:

### 1. No client-order-id — the venue assigns the id

Finam mints a `client_order_id` and keeps a `cid → order_id` cache;
BCS mints a `clientOrderId` that doubles as the server id. Alor accepts
**no** caller-supplied id: the placement response returns only
`{ message, orderNumber }`, and `orderNumber` (== the order object's
`id`) is the identity. So `Placement_handle_store` maps
`placement_id ↔ alor_order_id` and is populated **from the placement
response**, not before the call. A fill's parent (`orderno` / `orderNo`)
resolves straight back to the placement.

Because there is no client-side idempotency id, a blind transport-level
retry of an order POST could double-place. Each order POST therefore
carries an `X-REQID` header (`portfolio;nanos`); Alor deduplicates on
it, so the `Http_transport` stale-keepalive retry stays safe.

Alor does, however, accept a free-text `comment` (≤100 chars) that it
echoes back on order updates — the only client-side handle it offers.
The adapter stamps the saga's `placement_id` there. This restores the
recovery property Finam/BCS get from minting a client-order-id *before*
the call: if a placement POST lands at the venue but its response is
lost, the order is still identifiable at Alor by `comment`, so the
`placement_id ↔ server-id` mapping can be re-derived (a `GET /orders`
reconcile by `comment`) rather than being permanently lost. The
happy-path mapping is still recorded from the placement response's
`orderNumber`; `comment` is the durable anchor, not the fast path.
(Trades carry only the server order id `orderno`, not `comment`, so
trade→placement linkage always goes through the server id.)

### 2. WS multiplex correlated by `guid`, not by subscription key

Like Finam, Alor multiplexes every stream on one socket. Unlike Finam
(whose data frames echo a `subscription_key` naming the instrument and
timeframe), Alor data frames are `{ data, guid }` with **no** channel
or instrument marker — a bar payload is bare OHLCV. The bridge
therefore keeps a `guid → target` registry (`Bars (instrument,
timeframe) | Trades`), enriches each inbound frame back into a typed
`Ws.event`, and resubscribes on reconnect reusing the original guids so
the registry stays valid. The JWT rides inside each subscribe message
(`token` field), not a header.

### 3. Status has no "partially filled" token

Alor order status is only `working | filled | canceled | rejected`. A
partially-executed order stays `working` with a non-zero
`filledQtyBatch`. `Wire.status_of_wire` therefore derives
`New / Partially_filled / Filled` from the filled/quantity split rather
than from a wire token.

Auth is a hybrid of the two existing flows: a BCS-style refresh-token
exchange (`POST {oauth}/refresh?token=…` → `{ AccessToken }`) but, as
Alor returns no `expires_in` and never rotates the refresh-token,
expiry comes from the JWT's own `exp` claim (decoded as in
`Finam.Auth`) and no `Token_store` is wired in — the refresh-token is
read once from `ALOR_SECRET`.

Account calls (cancel, get-order, trades) are keyed by
`(exchange, portfolio)`. `portfolio` is baked into the adapter;
`exchange` is derived from the instrument's MIC for instrument-scoped
calls and falls back to `default_exchange` (MOEX) for the account-wide
trades feed — making one adapter instance effectively single-exchange,
matching BCS's MOEX-only posture.

## Consequences

- Routing to Alor is a config choice (`broker.alor`) with no change to
  any sibling BC or shared type — the ACL did its job (ADR 0015).
- The adapter is a pure recognizer of venue facts, emitting per-trade
  `Trade_executed` with no fill aggregation (ADR 0029); the OrderTicket
  remains the sole fill aggregator.
- **Single-exchange per instance.** A multi-exchange Alor portfolio
  would need the exchange stored alongside the order id in the
  placement store — a localised follow-up.
- **No order-state push; fills only.** The adapter subscribes to
  `TradesGetAndSubscribeV2` (fills) but not `OrdersGetAndSubscribeV2`
  (order-state). This is consistent with Finam (account-wide trades
  only) and BCS (execution-status channel, non-fill lifecycle events
  dropped), and with the broker BC's current event vocabulary
  (`Remote_bar_updated` + `Trade_executed` only — there is no
  `Order_state_changed` domain event yet). The cost, confirmed against
  the OsEngine production connector which *does* take the order-state
  push: venue-initiated terminal transitions that produce no
  trade — async `rejected`, plain `canceled`/expiry — are not observed
  as push events; they surface only via a `GET /orders` poll. A push
  `Order_state_changed` is a cross-adapter follow-up (it would touch
  Finam/BCS symmetrically and add a new domain event), deliberately out
  of scope for this adapter.

- **Stop / stop-limit not yet supported.** `place_order` handles market
  and limit; the domain stop kinds raise (surfacing as `Order_unreachable`)
  rather than mis-routing to a limit, until the dedicated Alor stop
  endpoints (condition / triggerPrice body) are wired.
- **Quantity is in lots.** Like BCS, the adapter truncates the port's
  decimal quantity to integer lots on submit, and reads the explicit
  lot fields (`qtyBatch` / `filledQtyBatch`) on orders and fills — not
  the ambiguous legacy `qty`. This keeps fills denominated the same way
  as the submitted (lot) quantity, so the OrderTicket reconciles
  correctly. The trade-off: Alor's `value` (cash notional) equals
  `price × qtyUnits` (shares), so `price × qtyBatch` is off from the
  cash notional by the lot size. That lots-vs-shares gap is system-wide
  (BCS shares it) — settling it means choosing one unit end-to-end
  (sizing → submit → reservation → fill), out of scope for this adapter.

## References

- ADR 0015 — Broker domain model (the abstraction this adapter defends).
- ADR 0029 — Per-trade `Trade_executed`, no broker-side aggregation.
- `docs/architecture/transport-supervisor.md` — the WS-primary /
  REST-fallback machinery Alor reuses (multiplexed-socket case, as Finam).
