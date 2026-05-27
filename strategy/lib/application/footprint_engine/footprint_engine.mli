(** Footprint strategy engine — the order-flow analogue of {!Live_engine}.

    Receives sealed footprint bars from a {!Pipe.Stream.t}, feeds them
    into a {!Strategies.Footprint_strategy.t}, and publishes every
    non-Hold {!Signal.t} as a
    {!Strategy_integration_events.Signal_detected_integration_event.t}.
    Pure alpha emitter — same contract as {!Live_engine}, but driven by
    the footprint feed (which carries real delta) rather than candles. *)

open Core

type config = {
  strategy : Strategies.Footprint_strategy.t;
  instrument : Instrument.t;
  strategy_id : string;
}

type t

module Signal_detected = Strategy_integration_events.Signal_detected_integration_event

val make : config:config -> publish_signal_detected:(Signal_detected.t -> unit) -> t

val on_footprint : t -> Footprint_bar.t -> unit
(** Feed one sealed footprint bar. Re-entrant-safe via an internal
    mutex; idempotent on older-or-equal timestamps. *)

val run : t -> source:Footprint_bar.t Pipe.Stream.t -> unit
(** Stream-driver variant: pulls footprint bars from [source] and feeds
    them via {!on_footprint}. Blocks — invoked inside a daemon fiber. *)
