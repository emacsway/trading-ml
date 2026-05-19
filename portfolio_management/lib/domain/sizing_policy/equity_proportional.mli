(** Equity-proportional sizing — the canonical default.

    Per-leg quantity: [target_qty = book_equity × weight / mark].

    For a {!Construction_intent.Scalar} intent the per-leg
    weight is [direction × strength] in [\[-1, 1\]]; for a
    {!Construction_intent.Coupled} intent the weight is the
    leg's pre-normalised signed weight (the [Σ |w| ≤ 1]
    invariant on the intent ensures the resulting gross
    notional does not exceed [book_equity]).

    Behaviour at edges, by design:
    - non-positive [mark] for an instrument → that leg's
      [target_qty] is zero (sentinel rather than exception, so
      a stale mark cache cannot stop the rest of the proposal);
    - zero [book_equity] → every leg's [target_qty] is zero;
    - {!Direction.Flat} scalar intent → singleton list with
      [target_qty] zero.

    The {!Coupling.t} on the input intent (if {!Coupled})
    propagates to every output leg; scalar intents emit
    [coupling = None]. Why3 (sizing_policy.mlw / coupling.mlw)
    captures ratio-preservation and sign-preservation for
    downstream clip proofs.

    [config] is [unit] — this policy has no tuneable knobs;
    capital allocation between books lives in {!Risk_config}'s
    [risk_budget_fraction], not here. *)

type config = unit

val name : string
(** ["equity_proportional"]. *)

val size :
  config ->
  book_equity:Decimal.t ->
  mark:(Core.Instrument.t -> Decimal.t) ->
  volatility:(Core.Instrument.t -> Decimal.t option) ->
  Common.Construction_intent.t ->
  Common.Target_proposal.t
