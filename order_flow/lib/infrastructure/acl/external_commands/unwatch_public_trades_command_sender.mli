(** Hexagonal Adapter: releases an instrument's public tape by serialising
    an {!Unwatch_public_trades_command.t} and publishing it on
    [in-memory://broker.unwatch-public-trades-command]. The order_flow
    factory calls this when a footprint subscription releases an
    instrument's last watched boundary (the demand registry's
    [Last_for_instrument] transition). *)

open Core

val make : bus:Bus.bus -> instrument:Instrument.t -> unit
