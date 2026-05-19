(** Construction-time risk clipping. Reduces leg [target_qty]
    values so the proposal stays within configured limits.
    Pure transformation; no events.

    Two clipping passes, applied in order:

    1. Per-instrument: each leg's notional [|target_qty| × mark]
       is capped at [limits.max_per_instrument_notional].
       Independent legs ([coupling = None]) are clipped one by
       one (sign-preserved). Legs sharing a {!Coupling.t} are
       treated as a single group: the entire group is scaled
       by a {b common} factor sufficient to bring its worst-
       offending leg under the cap — so inter-leg ratios that
       encode β-hedge symmetry, basket weights, etc., are
       preserved by construction.

    2. Gross-exposure: if the post-step-1 sum of leg notionals
       exceeds [limits.max_gross_exposure], every leg is scaled
       by a single common factor. Ratios survive this pass for
       all legs (coupled or not). *)

val clip :
  limits:Values.Risk_limits.t ->
  mark:(Core.Instrument.t -> Decimal.t) ->
  Common.Target_proposal.t ->
  Common.Target_proposal.t
(** Pure: same input → same output. The mark callback is total
    (returns [Decimal.zero] for unknown instruments) — the caller
    is responsible for providing prices for every instrument in
    the proposal. *)
