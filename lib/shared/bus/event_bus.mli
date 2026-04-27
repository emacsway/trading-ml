(** In-memory event bus: pub/sub fan-out for integration events.

    An integration event is a fact about something that happened in
    one BC, broadcast to any other BC that cares. Multiple
    subscribers per event type is the norm — the workflow that
    issued the originating command, the SSE bridge, an audit log,
    a metrics publisher.

    Synchronous: [publish] invokes all current subscribers in
    subscription order and returns once they've all returned.
    No queueing, no back-pressure, no thread safety — fits an
    InMemory single-fiber composition. Swap to [Eio.Stream]-backed
    when concurrency arrives.

    Subscriptions are reified as values returned from {!subscribe}
    so callers can {!unsubscribe} when their lifetime ends — the
    sync-wrapper pattern in [place_order_workflow] subscribes,
    runs, then unsubscribes. *)

type 'a t

type subscription

val create : unit -> 'a t

val subscribe : 'a t -> ('a -> unit) -> subscription
(** Add a subscriber. Returned handle identifies it for {!unsubscribe}. *)

val unsubscribe : 'a t -> subscription -> unit
(** Remove the subscriber identified by [subscription]. No-op if
    the handle is unknown to this bus (e.g., already removed, or
    came from another bus instance — the runtime doesn't tag). *)

val publish : 'a t -> 'a -> unit
(** Broadcast to all current subscribers, in subscription order. *)
