(** Implementation Shortfall (Almgren-Chriss) — parameters.

    Precomputes an optimal trading trajectory minimising the
    convex combination of expected market impact and
    timing-risk variance:

      minimise  E[cost] + λ × Var[cost]

    Closed-form solution (constant volatility σ, linear temporary
    impact η, no permanent impact, no jumps):

      x(t) = X × sinh(κ × (T − t)) / sinh(κ × T)
      κ = sqrt(λ × σ² / η)

    where [x(t)] is the remaining quantity at time [t]. The
    trajectory is precomputed at init across [n_slices] uniform
    sub-intervals of [[start_at, start_at + window_seconds]].

    The [risk_aversion] (λ), [volatility] (σ), and
    [temp_impact_eta] (η) parameters are operator-supplied —
    market-data-driven adaptation is a deferred refinement.

    Invariants:
    - [n_slices > 0], [window_seconds > 0];
    - [volatility ≥ 0];
    - [risk_aversion > 0];
    - [temp_impact_eta > 0]. *)

type t = private {
  n_slices : int;
  window_seconds : int;
  start_at : int64;
  volatility : float;
  risk_aversion : float;
  temp_impact_eta : float;
}

val make :
  n_slices:int ->
  window_seconds:int ->
  start_at:int64 ->
  volatility:float ->
  risk_aversion:float ->
  temp_impact_eta:float ->
  t
(** Raises [Invalid_argument] on any invariant violation. *)
