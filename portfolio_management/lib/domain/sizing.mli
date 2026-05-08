(** Construction-time sizing service.

    Translates an alpha-mind directional opinion ([strength] in
    [0, 1]) plus the book's current equity into a target position
    size, capped by a per-instrument notional limit.

    Algebraically distinct from {!Portfolio_management.Risk_policy.clip}:
    [from_strength] {b creates} a target_qty from primitives;
    [Risk_policy.clip] {b shrinks} an already-built target_proposal
    to fit limits. The two operations have opposite shapes
    (construct vs. fit-to-fit) and different invariants — they live
    in different sub-trees of [domain/] for that reason.

    Migrated from [Strategy.Engine.Risk.size_from_strength] as part
    of plan M3: this is the construction step that PM's
    alpha-driven domain-event handler will run before
    {!Risk_policy.clip}.

    Pure: same inputs → same output. *)

val from_strength :
  equity:Decimal.t ->
  price:Decimal.t ->
  max_per_instrument_notional:Decimal.t ->
  strength:float ->
  Decimal.t
(** [from_strength ~equity ~price ~max_per_instrument_notional ~strength]
    sizes a position from a fraction of equity, clamped by the
    per-instrument notional cap.

    - [strength] is clamped to [\[0, 1\]]; out-of-range values do
      not raise.
    - [budget = min(equity × strength, max_per_instrument_notional)].
    - Returns [budget / price] when [price > 0]; returns
      [Decimal.zero] when [price = 0] (degenerate inputs are
      tolerated rather than raised — matches the original
      [Engine.Risk.size_from_strength] sentinel behaviour). *)
