(** POV — Percent Of Volume — strategy.

    Targets [participation_rate × cumulative_observed_volume] as
    the cumulative emitted quantity. Each incoming [Volume_bar]
    grows the observed volume and unlocks a (possibly zero) next
    emission to maintain the rate. The volume feed is deferred
    today; with the [Disabled] adapter POV observably waits
    rather than silently executing as Immediate.

    Slice size on each Volume_bar:
      delta_target = (observed' × rate) − emitted_so_far
      emit_qty     = min(remaining, max(0, delta_target))
    Only emits when [emit_qty > 0].

    Ignores: [Tick], [Price_quote], [Placement_acknowledged],
    [Placement_filled]. Terminal on [Placement_rejected /
    unreachable / cancelled]. *)

(*@ function dec_raw (d : Decimal.t) : integer *)

type state

val init :
  intent:Values.Trade_intent.t ->
  params:Values.Pov_params.t ->
  now:int64 ->
  state * Decision.t
(*@ s, d = init ~intent ~params ~now
    requires dec_raw intent.Values.Trade_intent.total_quantity > 0
    ensures d.Decision.submit = []
    ensures d.Decision.terminal = Decision.Continue *)

val on_event : state -> Input.t -> now:int64 -> state * Decision.t

val is_complete : state -> bool
