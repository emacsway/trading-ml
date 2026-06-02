open Core

let make ~bus : instrument:Instrument.t -> unit =
  let publish =
    Bus.publish
      (Bus.producer bus ~uri:"in-memory://broker.unwatch-public-trades-command"
         ~serialize:(fun (v : Unwatch_public_trades_command.t) ->
           Yojson.Safe.to_string (Unwatch_public_trades_command.yojson_of_t v)))
  in
  fun ~instrument ->
    let cmd : Unwatch_public_trades_command.t =
      { symbol = Instrument.to_qualified instrument }
    in
    publish cmd
