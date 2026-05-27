(** Bar boundary policy — what ends one footprint bar and starts the
    next.

    Only [Time] is implemented in this round. The type is a variant so
    that the planned [Volume]/[Tick] boundaries drop in as new cases
    rather than a rewrite. They differ structurally, not by parameter
    alone — see {!admits_time_close} — so the polymorphic seam lives in
    the type, not in a numeric field.

    A [Time] bar's membership is a pure function of a print's timestamp
    ({!bucket_start}); it is stateless, which is exactly what the
    fold-order independence argument exploits. Volume/Tick membership
    depends on the running total of the open bar, so when added it will
    be decided by the aggregate, not here. *)

type t = Time of Core.Timeframe.t

val admits_time_close : t -> bool
(** Whether a bar under this boundary can close from the passage of
    time alone, with no further prints. A [Time] bar must close at its
    period edge even in a silent market, so [true]. Volume/Tick bars
    only close on the print that crosses the threshold, so they will be
    [false]. The live application layer uses this to drive a
    clock-triggered flush; in backtest a [Time] bar closes lazily on
    the first print of the next bucket. *)
(*@ r = admits_time_close b
    ensures match b with Time _ -> r = true *)

val period_seconds : t -> int
(** Bar length in whole seconds for a [Time] boundary
    ([Core.Timeframe.to_seconds]); always positive. *)
(*@ r = period_seconds b
    ensures r > 0 *)

val bucket_start : t -> ts:int64 -> int64
(** Canonical open timestamp of the bar containing [ts]. For [Time tf],
    [ts] floored to the period: [ts - (ts mod period)]. Two prints
    share a [Time] bar iff their [bucket_start] coincide; a strictly
    greater [bucket_start] means the print opens a later bar, a smaller
    one means it is late for an already-passed bucket. Requires
    [ts >= 0] (unix epoch). *)
