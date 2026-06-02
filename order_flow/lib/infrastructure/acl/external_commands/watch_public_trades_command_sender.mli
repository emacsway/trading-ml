(** Hexagonal Adapter: requests an instrument's public tape from the broker
    BC by serialising a {!Watch_public_trades_command.t} and publishing it
    on [in-memory://broker.watch-public-trades-command]. The order_flow
    factory calls this when a footprint subscription first needs an
    instrument's tape (the demand registry's [First_for_instrument]
    transition). Domain-typed at the surface ([Instrument.t]); the wire
    [symbol] is built via [Instrument.to_qualified] inside the closure. *)

open Core

val make : bus:Bus.bus -> instrument:Instrument.t -> unit
