(** Stateful inbound handler for {!Footprint_completed_integration_event.t}.

    Mirrors the bar handler: buffers decoded footprint bars in an
    internal {!Eio.Stream.t} and exposes them as a pull-driven
    {!Pipe.Stream.t} via {!source}, which the footprint engine drains.
    {!handle} is the bus callback; it drops events whose instrument does
    not match [instrument], translating the rest into the strategy BC's
    own {!Common.Footprint_bar.t} view. *)

module Footprint_completed = Footprint_completed_integration_event

type t

val make : capacity:int -> t
val source : t -> Common.Footprint_bar.t Pipe.Stream.t
val handle : t -> instrument:Core.Instrument.t -> Footprint_completed.t -> unit
