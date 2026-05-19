(** Desired position in one instrument, signed: positive = long,
    negative = short, zero = flat. Identified inside its book by
    the [instrument] key — at most one [Target_position.t] per
    [(book_id, instrument)] in any well-formed Target_portfolio.

    [coupling], when [Some _], marks this leg as part of a
    coupling group whose inter-leg ratios are a load-bearing
    domain invariant (β-hedge symmetry for pair construction,
    basket weights for factor portfolios, etc.).
    {!Portfolio_management.Risk_policy.clip} treats every leg
    sharing the same {!Coupling.t} as a single unit when
    scaling — preserving ratios that would otherwise be broken
    by per-instrument clipping. [None] denotes an independent
    leg; sizing or downstream policies that do not encode
    inter-leg invariants emit [None]. *)

type t = {
  book_id : Book_id.t;
  instrument : Core.Instrument.t;
  target_qty : Decimal.t;  (** signed *)
  coupling : Coupling.t option;
}

val equal : t -> t -> bool
(** Structural equality across all fields, including [coupling]. *)
