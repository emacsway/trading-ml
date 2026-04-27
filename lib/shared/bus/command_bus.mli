(** In-memory command bus: address-style 1-to-1 dispatch.

    A command names a single recipient and demands action. By
    construction [Command_bus.t] holds at most one handler per
    instance — a runtime guard catches double registration as a
    composition-root error rather than letting the second handler
    silently shadow the first.

    Synchronous: [send] runs the handler in the caller's fiber and
    returns once the handler returns. Outcomes are observed via
    integration events on a separate {!Event_bus}; the command
    bus itself doesn't carry results.

    One [t] per command type. The composition root creates buses
    per type and wires the single handler. *)

type 'a t

val create : unit -> 'a t

exception Already_registered

val register_handler : 'a t -> ('a -> unit) -> unit
(** Bind THE handler. Raises {!Already_registered} on the second
    call — composition-root invariant: exactly one owner per
    command type. *)

exception No_handler

val send : 'a t -> 'a -> unit
(** Dispatch synchronously. Raises {!No_handler} if [send] runs
    before [register_handler] — also a composition-root error. *)
