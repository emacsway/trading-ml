(** Footprint demand registry: which boundaries are watched per instrument,
    refcounted, plus the boundary fan-out the ingest path uses.

    Two refcount levels, both load-bearing:

    - {b Boundary level} — concurrent watchers of the same
      [(instrument, boundary)] share one forming bar; a boundary stops
      being aggregated only when its last watcher drops it. This is what
      {!boundaries_for} reads.
    - {b Instrument level} — {!watch} / {!unwatch} report
      [First_for_instrument] / [Last_for_instrument] on the 0->1 / 1->0
      transitions of {e any} boundary for an instrument, so the composition
      root can pull (or release) that instrument's public tape on demand
      (the cross-BC piece — a non-watchlist instrument has no tape until a
      footprint subscription asks for it).

    The operator's default boundary is {e not} held in the registry — it is
    always present in {!boundaries_for}'s output, so footprints keep being
    built for any instrument with a tape even when nobody has watched it
    explicitly. Pure in-memory state, no bus, no clock — directly testable. *)

open Core

type t

type watch_outcome =
  | First_for_instrument
      (** This watch is the first for the instrument — no boundary was
          watched for it before. The caller should ensure the instrument's
          public tape is flowing. *)
  | Already_watching
      (** The instrument already had at least one watched boundary; the
          tape is assumed already requested. *)

type unwatch_outcome =
  | Last_for_instrument
      (** This unwatch dropped the instrument's last watched boundary. The
          caller may release the instrument's public tape. *)
  | Still_watching
      (** Other boundaries remain watched for the instrument (or there was
          nothing to release); the tape stays requested. *)

val create : default_boundary:Order_flow.Footprint.Values.Bar_boundary.t -> t
(** [default_boundary] is the operator's always-on boundary, included in
    every {!boundaries_for} result but never refcounted. *)

val watch :
  t ->
  instrument:Instrument.t ->
  boundary:Order_flow.Footprint.Values.Bar_boundary.t ->
  watch_outcome
(** Register one watcher of [(instrument, boundary)] and report whether it
    is the first boundary watched for [instrument]. *)

val unwatch :
  t ->
  instrument:Instrument.t ->
  boundary:Order_flow.Footprint.Values.Bar_boundary.t ->
  unwatch_outcome
(** Release one watcher of [(instrument, boundary)] and report whether it
    dropped the instrument's last watched boundary. An unwatch with no
    matching prior watch is a benign no-op reported as [Still_watching]. *)

val boundaries_for : t -> string -> Order_flow.Footprint.Values.Bar_boundary.t list
(** Boundaries a print for [symbol] (qualified) must be fanned into: the
    always-on default plus every currently-watched boundary, deduplicated
    by token. *)
