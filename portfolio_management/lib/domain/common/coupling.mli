(** Identifier of a coupling group: a set of {!Target_position.t}
    legs that must be treated as a single unit by downstream
    transformations.

    Concretely: when {!Risk_policy.clip} would otherwise reduce
    legs of a coupled construction (a pair, a basket, a factor
    portfolio) independently, the presence of a shared
    [Coupling.t] tells [clip] to scale the entire group by one
    common factor — preserving inter-leg ratios that encode
    domain invariants (β-hedge symmetry, basket weights, etc.).

    The identifier is opaque: callers do not interpret it, only
    compare it. Producers (pair_mean_reversion, future basket
    construction) generate a fresh [Coupling.t] per emitted
    intent; the value travels with each leg through sizing and
    clipping, then becomes irrelevant at
    {!Target_portfolio.apply_proposal} time. *)

type t

val make : ?source:string -> int64 -> t
(** [make ?source occurred_at] builds a coupling identifier.
    [occurred_at] is the same epoch second the construction
    policy timestamps the originating intent with; [source] is
    an optional disambiguator if multiple coupling groups can
    occur at the same instant (e.g. several pair policies on
    one book). The pair-(occurred_at, source) is hashed into a
    short opaque key — equality below compares those keys. *)

val to_string : t -> string
(** Stable rendering for logs and audit; not the identity. *)

val equal : t -> t -> bool

val compare : t -> t -> int
