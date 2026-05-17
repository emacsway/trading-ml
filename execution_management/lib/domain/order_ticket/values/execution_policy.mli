(** BC-internal fallback policy used when the upstream trader
    intent omits the [execution_directive] on the wire. Today the
    policy is constant — [Immediate] — but the surface is here so
    a future per-book / per-instrument / time-of-day policy can
    land without changing every caller. *)

val default : Execution_directive.t
