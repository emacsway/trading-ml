# WebSocket protocol layer

`broker/lib/infrastructure/websocket/` is the broker-agnostic
WS client our ACL adapters build on. Two files matter for
correctness: `client.ml` (RFC 6455 framing — handshake, frame
codec, control-frame handling) and `resilient.ml` (reconnect
with backoff, server-driven heartbeat, decoupling of socket
reads from consumer work).

The interesting architectural property is how heartbeats are
kept responsive under load. Most providers — BCS, Finam — push
an RFC 6455 Ping every ~30 s and close the connection if a
Pong does not come back fast enough. The full constraint chain
is:

1. The auto-pong must happen on the reader fiber's iteration.
   `Client.recv` answers Pings inline (see `client.ml:67-72`),
   so the only thing the rest of the system has to do is keep
   calling `recv` regularly.
2. The reader fiber must not be blocked by user-supplied
   business logic. Otherwise a slow `on_text` handler — say,
   one that does a synchronous downstream publish or, worse, a
   REST round-trip — would freeze recv long enough for the
   server-side heartbeat watchdog to fire.

That second invariant is what `Resilient` defends, with a
two-fiber split.

## Reader and consumer

```
Server frames
     │
     ▼
┌──────────────────────┐
│ reader fiber         │  Client.recv (auto-Pong on Ping)
│                      │       │
│                      │       ▼
│                      │  Eio.Stream.add  ──┐  (bounded, capacity 1024)
└──────────────────────┘                    │
                                            ▼
                                ┌──────────────────────┐
                                │ consumer fiber       │
                                │   loop {             │
                                │     payload :=       │
                                │       Stream.take    │
                                │     config.on_text   │
                                │       payload        │
                                │   }                  │
                                └──────────────────────┘
                                            │
                                            ▼
                                  bridge / supervisor /
                                  broker / application
```

The reader does two things per frame: pull bytes off the
socket, push a parsed text payload into the queue. Both are
microsecond-scale. The Ping → Pong handshake happens inside
`recv` before the payload ever reaches the queue, so the
consumer's wall-clock cost is irrelevant to heartbeat
correctness.

## Queue capacity

`Eio.Stream.create 1024` — bounded, mainly to avoid unbounded
memory growth if a consumer wedges entirely. A high-water mark
warning fires at ~80 % (`Log.warn "consumer queue at .../1024
— slow on_text handler suspected"`) so a deteriorating
consumer is observable before the queue saturates and starts
backpressuring the reader. The warn is one-shot per occurrence
— it clears when the queue drains back below 40 %, so a
chronically slow consumer produces a periodic signal rather
than a spam stream.

If the queue ever does saturate (consumer truly stuck for
1024 frames of input), `Eio.Stream.add` blocks and reader
heartbeat correctness is back on the line. That is the failure
mode we want operators to catch via the warning **before** it
matters.

## Reconnect interaction

The reader fiber's lifetime is one socket session — it
respawns inside `reconnect` whenever a session ends. The
consumer fiber is spawned once at `Resilient.create` and lives
the lifetime of the resilient handle. The queue is the same
across reconnects, so any frames that landed in the queue
just before disconnect are still drained by the consumer in
order. The next session's reader pushes onto the same queue
seamlessly.

On `close`, both fibers are cancelled by the parent switch's
tear-down. `Eio.Stream.take` raises `Cancelled` and the
consumer exits cleanly.

## Test coverage gap

There is no in-process unit test that exercises the
reader / consumer race directly. Doing so requires faking a
`Client.t` — its underlying `Eio.Flow` and `Eio.Buf_read` — or
running an in-process WebSocket server fixture, neither of
which exists today.

The protocol-layer correctness is covered indirectly:

- `websocket_frame_test` (88-test broker unit suite)
  verifies RFC 6455 framing and the auto-Pong path through
  `Frame.decode`.
- Live smoke against BCS / Finam (4-test alias)
  exercises the real reader / consumer pair against the real
  brokers; a regression here would show up as broker-side
  disconnects within ~30 s of a slow downstream handler.

A standalone unit-test fixture is a worthwhile follow-up but
not on the critical path — the current code structure makes
the invariant readable, and live smoke remains the canonical
end-to-end check.

## See also

- [Transport supervisor](transport-supervisor.md) — the next
  layer up, which decides whether to feed the broker BC from
  this WS pipe or from REST polling.
- `broker/lib/infrastructure/websocket/client.mli` — handshake
  and frame-level surface.
- `broker/lib/infrastructure/websocket/resilient.mli` — the
  reconnect / heartbeat / queue plumbing.
