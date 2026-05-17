(** TWAP — Time-Weighted Average Price — strategy.

    Splits [intent.total_quantity] into [params.n_slices] equal
    pieces (the final slice carries the integer-division residue
    so [Σ slice_qty = total_quantity] exactly) and emits one slice
    per scheduled tick across [params.window_seconds] starting at
    [params.start_at].

    Tick schedule: slice [i] (0-indexed) is due at
    [start_at + i × (window_seconds / n_slices)] in seconds since
    epoch. Tick events whose [now] is below the next-due timestamp
    return [Decision.empty]; ticks at or after it emit one slice.

    Strategy is one-emission-per-tick. Multiple ticks at the same
    instant cannot double-emit. Late ticks past several due-slice
    boundaries emit only one slice (the next due one) — the
    aggregate's scheduler runs frequently enough that this never
    matters in practice.

    Terminal handling: any [Placement_rejected],
    [Placement_unreachable] or [Placement_cancelled] terminates
    the strategy as [Failed _] (TWAP doesn't retry slices; the
    aggregate may compensate the unfilled remainder). The strategy
    reports {!is_complete} = [true] only after all [n_slices]
    have been emitted AND no failure occurred. *)

(*@ function dec_raw (d : Decimal.t) : integer *)

type state

val init :
  intent:Values.Trade_intent.t ->
  params:Values.Twap_params.t ->
  now:int64 ->
  state * Decision.t
(** Construct the initial state. Returns [Decision.empty] (no
    immediate submit) — TWAP waits for the first scheduler tick
    whose [now ≥ params.start_at]. *)
(*@ s, d = init ~intent ~params ~now
    requires dec_raw intent.Values.Trade_intent.total_quantity > 0
    requires params.Values.Twap_params.n_slices > 0
    ensures d.Decision.submit = []
    ensures d.Decision.cancel = []
    ensures d.Decision.terminal = Decision.Continue *)

val on_event : state -> Input.t -> now:int64 -> state * Decision.t

val is_complete : state -> bool
