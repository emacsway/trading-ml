(** Per-book risk configuration aggregate. Owns the parameters
    that bound a book's construction-time behaviour.

    The aggregate separates two concepts that the previous
    {b notional_cap} placeholder conflated:

    - [risk_budget_fraction] — the {b sizing} primitive: the
      share of total account equity allocated to this book. A
      book with [risk_budget_fraction = 0.3] sizes positions
      against [0.3 × total_equity]. This is operator-level
      capital allocation between books — a deliberate config
      decision, not a derived quantity. Operating in a closed
      interval [\[0, 1\]]; the aggregate enforces.
    - [limits] — the {b clipping} primitive: absolute caps
      (per-instrument notional, gross exposure) the construction
      output must respect regardless of sizing. These come from
      regulators, prime brokers, or risk management mandates;
      they are NOT functions of equity.
    - [construction_source] — exactly one
      {!Common.Source.t} permitted to publish targets to this
      book. Encodes "one construction source per book" as a
      structural invariant rather than a coordination
      convention. {!Target_portfolio.apply_proposal}-side
      validation rejects proposals whose [source] does not
      match.

    The aggregate is small and value-shaped today (no events),
    but is modelled as an aggregate rather than a VO because:

    - it owns a per-book identity and lifecycle (creation,
      future re-configuration);
    - its invariants ([fraction ∈ \[0, 1\]], [limits.well_formed],
      [construction_source matched]) are load-bearing across
      the construction → clip → apply pipeline. *)

type t

val make :
  book_id:Common.Book_id.t ->
  risk_budget_fraction:Decimal.t ->
  limits:Risk.Values.Risk_limits.t ->
  construction_source:Common.Source.t ->
  t
(** [make ~book_id ~risk_budget_fraction ~limits
       ~construction_source] constructs the configuration.

    Raises [Invalid_argument] when [risk_budget_fraction] is
    outside [\[0, 1\]]. [limits] is already validated by
    {!Risk.Values.Risk_limits.make}. *)

val book_id : t -> Common.Book_id.t
val risk_budget_fraction : t -> Decimal.t
val limits : t -> Risk.Values.Risk_limits.t
val construction_source : t -> Common.Source.t

val book_equity : t -> total_equity:Decimal.t -> Decimal.t
(** [book_equity t ~total_equity] is the equity slice a sizing
    policy should treat as the book's capital, i.e.
    [risk_budget_fraction × total_equity]. *)

val authorises : t -> Common.Source.t -> bool
(** [authorises t s] is [true] iff [s] equals the
    [construction_source] this aggregate permits — the
    one-source-per-book invariant in predicate form. *)
