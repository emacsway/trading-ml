(** Implementation Shortfall — Almgren-Chriss optimal trajectory.

    Precomputes a slice schedule at init that minimises
    [E[cost] + λ × Var[cost]] under constant volatility σ, linear
    temporary impact η, and no permanent impact / jumps. The
    closed-form remaining-quantity function is

      x(t) = X × sinh(κ × (T − t)) / sinh(κ × T)
      κ    = sqrt(λ × σ² / η)

    where [X] is [intent.total_quantity], [T] is
    [params.window_seconds], and slices are uniformly spaced in
    time. Slice [i] (for [i = 1 .. n_slices]) emits
    [x(t_{i-1}) − x(t_i)]; the final slice absorbs the
    float-arithmetic residue so [Σ slice_qty = total_quantity]
    exactly.

    Lifecycle: emits on [Tick] (one slice per scheduled tick);
    ignores [Volume_bar] / [Price_quote] today (adaptive variant
    is a deferred refinement). Rejection / unreachable /
    cancelled on any slice terminates the strategy as Failed.

    Note: when [σ = 0], the optimisation degenerates to TWAP
    (linear x(t) = X × (1 − t/T)). The closed form handles this
    correctly via the limit; the strategy still emits the
    boundary-condition residue on the final slice. *)

(*@ function dec_raw (d : Decimal.t) : integer *)

type state

val init :
  intent:Values.Trade_intent.t ->
  params:Values.Implementation_shortfall_params.t ->
  now:int64 ->
  state * Decision.t
(*@ s, d = init ~intent ~params ~now
    requires dec_raw intent.Values.Trade_intent.total_quantity > 0
    ensures d.Decision.submit = []
    ensures d.Decision.terminal = Decision.Continue *)

val on_event : state -> Input.t -> now:int64 -> state * Decision.t

val is_complete : state -> bool
