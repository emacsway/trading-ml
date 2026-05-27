(** Footprint-strategy signature — the order-flow analogue of {!Strategy}:
    stream sealed footprint bars in, emit {!Signal.t} out.

    Kept separate from {!Strategy} because a footprint carries the signed
    delta (and, later, per-price clusters) that a candle does not;
    collapsing it to a candle would discard exactly the order-flow
    information these strategies exist to use. Same deterministic
    state-machine contract — identical inputs yield identical outputs. *)

open Core

module type S = sig
  type state
  type params

  val name : string
  val default_params : params
  val init : params -> state
  val on_footprint : state -> Instrument.t -> Footprint_bar.t -> state * Signal.t
end

type t

val make : (module S with type state = 's and type params = 'p) -> 'p -> t
val default : (module S with type state = 's and type params = 'p) -> t
val on_footprint : t -> Instrument.t -> Footprint_bar.t -> t * Signal.t
val name : t -> string
