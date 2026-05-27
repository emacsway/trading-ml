(** Aggregate root: one footprint bar, built print-by-print from the
    public tape and sealed at its boundary.

    Lifecycle [Forming -> Sealed]. A [Forming] bar absorbs prints whose
    timestamp falls in its bucket; [seal] freezes it and emits the
    completed footprint. A [Sealed] bar is immutable — the late-data
    policy lives at the edges, not in mutation.

    Single-bar consistency boundary: this aggregate owns exactly one
    bar. Rolling to the next bar (seal current, open next) is sequenced
    by the application layer, which holds the current bar per
    instrument — mirroring how the [Portfolio] handler holds its state.

    Two running accumulators, [volume] and [delta], are the source of
    truth for the bar's totals (their conservation laws are proved in
    [footprint.mlw]); [clusters] carries the per-price breakdown from
    which the Point of Control, high and low are derived at seal. Every
    [clusters] entry is itself conservation-correct by
    [Cluster.add_conserves_total], so the breakdown sums to [volume] by
    construction. *)

(*@ function dec_raw (d : Decimal.t) : integer *)

module Values : module type of Values
module Events : module type of Events

type status = Forming | Sealed

type t = private {
  instrument : Core.Instrument.t;
  boundary : Values.Bar_boundary.t;
  status : status;
  open_ts : int64;  (** bucket-aligned bar open, unix epoch seconds *)
  open_price : Decimal.t;  (** first print's price *)
  close_price : Decimal.t;  (** last absorbed print's price *)
  volume : Decimal.t;  (** running total volume *)
  delta : Decimal.t;  (** running bar delta (buy - sell) *)
  clusters : Values.Cluster.t list;  (** ascending by price *)
}

val open_ :
  instrument:Core.Instrument.t ->
  boundary:Values.Bar_boundary.t ->
  first:Values.Print.t ->
  t * Events.Bar_opened.t
(** Open a [Forming] bar at [first]'s bucket and absorb [first]. The
    bar's [open_ts] is [first.ts] floored to the boundary period; its
    [open_price] is [first]'s price. *)

type placement =
  | In_bar  (** [print] belongs to this bar's bucket — [absorb] it *)
  | Opens_later  (** [print] belongs to a later bucket — seal and open anew *)
  | Late  (** [print] belongs to an earlier, already-passed bucket *)

val classify : t -> Values.Print.t -> placement
(** Where a print sits relative to this bar, by comparing its
    [bucket_start] to [open_ts]. Pure; intended for a [Forming] bar.
    The application acts on the result: [In_bar -> absorb],
    [Opens_later -> seal then open_], [Late -> reject] (the late-data
    policy — a [Sealed] bar is never reopened). *)

val absorb : t -> Values.Print.t -> t
(** Route a print into the bar: add its size to the price-level cluster
    and to the running totals, and advance [close_price].

    Precondition: [status = Forming] and [classify b p = In_bar]. The
    application guarantees both before calling; the proof obligation
    that a sealed bar is never mutated is discharged by this contract,
    not re-checked at runtime. *)
(*@ b' = absorb b p
    ensures b'.status = b.status *)

val seal : t -> t * Events.Footprint_completed.t
(** Freeze a [Forming] bar into [Sealed] and emit its completed
    footprint: OHLCV from the bar's own prints, the accumulated [volume]
    and [delta], the Point of Control (price of the max-volume cluster,
    lowest price winning ties), and the per-price clusters. *)
(*@ (b', ev) = seal b
    ensures b'.status = Sealed
    ensures dec_raw ev.volume = dec_raw b.volume
    ensures dec_raw ev.delta = dec_raw b.delta *)
