open Core

let subscribe ~(cfg : Config.t) ~token ~guid ~(instrument : Instrument.t) () :
    Yojson.Safe.t =
  let group =
    match Routing.instrument_group_of cfg instrument with
    | Some g -> [ ("instrumentGroup", `String g) ]
    | None -> []
  in
  `Assoc
    ([
       ("opcode", `String "AllTradesGetAndSubscribe");
       ("code", `String (Routing.symbol_of instrument));
       ("exchange", `String (Routing.exchange_of cfg instrument));
       ("depth", `Int 0);
       ("includeVirtualTrades", `Bool false);
       ("format", `String "Simple");
       ("token", `String token);
       ("guid", `String guid);
     ]
    @ group)
