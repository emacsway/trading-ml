open Core

let make ~bus : instrument:Instrument.t -> unit =
  let publish =
    Bus.publish
      (Bus.producer bus ~uri:"in-memory://broker.watch-public-trades-command"
         ~serialize:(fun (v : Watch_public_trades_command.t) ->
           Yojson.Safe.to_string (Watch_public_trades_command.yojson_of_t v)))
  in
  fun ~instrument ->
    let cmd : Watch_public_trades_command.t =
      { symbol = Instrument.to_qualified instrument }
    in
    publish cmd
