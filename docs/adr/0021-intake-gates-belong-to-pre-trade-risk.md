# 0021. Intake gates (kill_switch, rate_limit) belong to pre_trade_risk

- Status: accepted
- Date: 2026-05-17
- Deciders: @emacsway

## Context

Two intake-time gates have lived in `execution_management` since
ADR 0011 first introduced them:

- **kill_switch** — a portfolio-wide drawdown circuit breaker.
  Tracks peak equity; trips when current equity falls below
  `peak × (1 − max_drawdown_pct)`. Once tripped, halts new
  intents until reset by an operator.
- **rate_limit** — a sliding-window cap on the rate of accepted
  intents. Defends against runaway strategies (a bug that
  generates intents in a tight loop). The original monolith's
  comment also cited broker API quotas; that's a separate concern
  belonging to the broker-dispatch path, not to intake.

Both gated `Trade_intent_approved` at saga start in EM's factory.
After ADR 0020 extracted the saga into `order_management`, the
gates had no natural home in either BC:

- **In EM** (transitional state after ADR 0020): gate at
  `Open_order_ticket_command` receipt. Wasteful — Account's
  reservation already lands before the gate trips, then EM has to
  publish `Release_command` to undo it.
- **In OM**: no equity-state ownership. Subscribing to
  `Reservation_filled` just to track equity is an artificial
  responsibility.

The right home was hiding in plain sight: **pre_trade_risk**.

## Decision

Move kill_switch and rate_limit (domain + tests + outbound IEs)
into `pre_trade_risk`. PTR's `Assess_trade_intent_command_workflow`
gains a gate check before the per-trade `Assessment.assess`:

```
PM   → Trade_intents_planned     → PTR
PTR   ↓
       try_intake?
         tripped (kill_switch) → publish Trade_submission_blocked
         throttled (rate_limit) → publish Trade_submission_blocked
         allowed →
           Assessment.assess →
             Approve → publish Trade_intent_approved → OM saga starts
             Reject  → publish Trade_intent_rejected (per-trade reason)
```

The gate enforcement at PTR has four advantages over EM:

1. **No wasted reservation.** Gate fires before
   `Trade_intent_approved` is published; OM never receives an
   intent the gate would have refused; Account is never asked to
   reserve cash for a refused intent.

2. **PTR already owns equity-state.** PTR subscribes to
   `Reservation_filled` (since the Risk_view feature) and its
   `Risk_view` domain holds the `equity = cash + Σ qty × mark`
   invariant. Adding kill_switch.update_equity to the existing
   handler is one line per call.

3. **PTR is the gate.** ADR 0011 framed PTR as the single
   approver of trader intents. Per-trade risk limits already
   live there. Drawdown circuit and intake throttle are
   conceptually one kind of "approve / refuse" decision — they
   fit the same role.

4. **EM becomes the clean EMS layer.** No intake plumbing, no
   equity tracking, no `Reservation_filled` subscription. EM
   owns the OrderTicket aggregate, the six strategies, and the
   broker dialog. Single responsibility.

### Two distinct signals

PTR now publishes three independent IE topics for intent
outcomes:

- `pre-trade-risk.trade-intent-approved` — gate passed, per-trade
  assessment approved
- `pre-trade-risk.trade-intent-rejected` — per-trade assessment
  refused (cash floor, gross exposure, leverage, zero price, …)
- `pre-trade-risk.trade-submission-blocked` — global intake gate
  refused (kill_switch or rate_limit), per-trade assessment never
  ran

`Trade_submission_blocked` is the new outbound for gate trips
(moved over from EM). `Trade_intent_rejected` keeps its existing
semantics — per-trade refusals only. The audit / SSE consumers
subscribe to whichever subset they need.

Two semantics, two IEs, no overload. Saga consumers (OM)
subscribe to `Trade_intent_approved` only and behave identically
under either form of refusal: no saga is started.

### Mid-batch trip behavior

PM publishes `Trade_intents_planned` carrying N legs. PTR
assesses each leg as a separate `Assess_trade_intent_command`.
If kill_switch trips after leg 3 (because a `Reservation_filled`
arrived between leg 3 and leg 4), legs 4..N are refused with
`trade_submission_blocked`. The earlier-approved legs proceed —
they were assessed when the gate was open, and stopping them
mid-saga is not the gate's job (running sagas continue under any
of the three placement options analysed in the design dialogue).

Kill_switch state is consulted under PTR's factory-level mutex,
so the race between assessments and Reservation_filled-driven
state updates is serialised.

### rate_limit interpretation

In the original monolith, rate_limit served two purposes
simultaneously: "against runaway strategies" (intake throttle)
and "respect broker API quotas" (submission throttle). With the
new architecture (intent → ticket → fan-out of N broker
submissions), these are different metrics and don't compose into
one cap.

This ADR moves only the **intake throttle** to PTR — its
historically-correct function. The original code gated at intake
in `check_gates` before reservation, which is the intake-throttle
semantic. The broker-API-quota use case is real (Finam, BCS
publish rate limits) but belongs in a separate broker-dispatch
throttle, plausibly inside EM or below the broker ACL; it is
not part of this ADR.

## Consequences

**Easier:**

- Gate enforcement is sync with assessment — no wasted
  Account-cycle on tripped intents.
- EM becomes a single-responsibility EMS layer; OM is a pure
  saga-only BC.
- PTR is now the single intake-decision authority. Adding new
  gate kinds (concentration limits, instrument blacklists,
  session-time policies) lands in the same place by the same
  pattern.
- The kill_switch-tracking handler reuses PTR's existing
  Reservation_filled subscription. One subscription, two
  side-effects.

**Harder:**

- PTR's factory grows: holds kill_switch ref + rate_limit ref +
  per-trip publishers. Still self-contained.
- `Trade_submission_blocked` is published by PTR on a new URI
  (`pre-trade-risk.trade-submission-blocked` vs. the previous
  `execution-management.trade-submission-blocked`). Telemetry /
  SSE consumers must update their subscriptions. The composition
  root (`bin/main.ml`) was the only existing consumer; updated.

**To watch for:**

- A future broker-dispatch throttle (the deferred half of the
  monolith's rate_limit) lands in EM under a different name and
  with broker-quota-aware configuration. Don't conflate it with
  PTR's intake rate_limit even if the implementation skeleton is
  similar.
- PTR's gate check holds a factory-level mutex around the
  rate_limit counter update. Per-trade `Assessment.assess` calls
  are serialised. Today's traffic doesn't approach a level where
  this matters; a future high-frequency intake source would
  justify a finer-grained model.

## References

- ADR 0011 — Risk-evacuation and Place-Order saga (original
  placement of kill_switch / rate_limit in EM).
- ADR 0020 — Order_management as a separate BC (the transitional
  state this ADR follows up on).
- ADR 0013 — Clock injection (PTR's gate uses `now : unit → int64`
  for rate_limit's sliding window).
