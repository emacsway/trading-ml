(** Decision of a portfolio-construction policy, expressed in
    {b dimensionless} form: what the policy wants to hold, not
    how many units that translates to. The conversion to units
    is the job of {!Sizing_policy} downstream; the bounding to
    risk caps is the job of {!Risk_policy.clip} after that.

    Two structurally distinct variants:

    - {!Scalar} — a single-asset directional view with
      conviction. The natural shape for alpha-mind sources
      ([direction, strength]).
    - {!Coupled} — a multi-leg intent whose inter-leg ratios
      encode a domain invariant the construction policy is
      asserting (β-hedge symmetry for pairs, basket weights for
      factor portfolios, etc). The shared {!Coupling.t} on each
      leg tells downstream clipping not to break the ratio.

    The variant choice is structural, not nominal: scalar and
    coupled intents are different shapes of decision, and the
    type makes that explicit. A future basket / factor variant
    plugs in as a new constructor without disturbing existing
    consumers. *)

type leg = { instrument : Core.Instrument.t; weight : Decimal.t }
(** A coupled leg: [weight] is signed and dimensionless
    ([positive = long, negative = short]). Conventions enforced
    at construction (see {!coupled}):
    - [Σ |weight| ≤ 1] across legs;
    - leg list is non-empty;
    - no duplicate instruments;
    - sorted by [Core.Instrument.compare]. *)

type t =
  | Scalar of {
      book_id : Book_id.t;
      instrument : Core.Instrument.t;
      direction : Direction.t;
      strength : Strength.t;
      source : Source.t;
      observed_at : int64;
    }
  | Coupled of {
      book_id : Book_id.t;
      legs : leg list;
      coupling : Coupling.t;
      source : Source.t;
      observed_at : int64;
    }

val scalar :
  book_id:Book_id.t ->
  instrument:Core.Instrument.t ->
  direction:Direction.t ->
  strength:Strength.t ->
  source:Source.t ->
  observed_at:int64 ->
  t
(** Smart constructor for {!Scalar}. Strength range and source
    validity are guaranteed by their respective VO constructors;
    this constructor adds no further checks. *)

val coupled :
  book_id:Book_id.t ->
  legs:leg list ->
  coupling:Coupling.t ->
  source:Source.t ->
  observed_at:int64 ->
  t
(** Smart constructor for {!Coupled}. Validates and normalises:
    - rejects empty [legs];
    - rejects duplicate [instrument]s within [legs];
    - rejects any leg with absolute weight strictly greater
      than [Decimal.one] (would already violate [Σ |w| ≤ 1]);
    - rejects [Σ |weight| > 1] across legs;
    - returns the leg list sorted by [Core.Instrument.compare]
      regardless of input order, so two structurally-equivalent
      intents are observationally equal.

    Raises [Invalid_argument] on any violation. *)

val book_id : t -> Book_id.t
val source : t -> Source.t
val observed_at : t -> int64
