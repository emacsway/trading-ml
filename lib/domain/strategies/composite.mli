(** Composite strategy: combines N child strategies under a voting
    policy. Implements [Strategy.S] so it's indistinguishable from a
    leaf — can be backtested, registered, or nested.

    Policies:
    - [Unanimous] — all children must agree (Hold = "no").
    - [Majority]  — >50% of all children.
    - [Any]       — at least one active voter.
    - [Adaptive]  — Sharpe-weighted ensemble: each child's vote is
      scaled by its rolling Sharpe ratio over [window] realized
      returns. Children that have been profitable get more influence;
      poorly-performing children are down-weighted toward zero. When
      all Sharpes are non-positive, falls back to equal weights. *)

open Core

type policy =
  | Unanimous
  | Majority
  | Any
  | Adaptive of { window : int }

type params = {
  policy : policy;
  children : Strategy.t list;
}

type state

val name : string
val default_params : params
val init : params -> state
val on_candle : state -> Instrument.t -> Candle.t -> state * Signal.t
