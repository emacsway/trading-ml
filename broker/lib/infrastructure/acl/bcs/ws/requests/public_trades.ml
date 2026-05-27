(* BCS market-data WS request for the public-trade (all-trades) channel:
   [dataType:2] (LastTrades), vs [dataType:1] for candles. *)

let envelope ~subscribe_type ~class_code ~ticker : Yojson.Safe.t =
  `Assoc
    [
      ("subscribeType", `Int subscribe_type);
      ("dataType", `Int 2);
      ( "instruments",
        `List [ `Assoc [ ("classCode", `String class_code); ("ticker", `String ticker) ] ]
      );
    ]

let subscribe = envelope ~subscribe_type:0
let unsubscribe = envelope ~subscribe_type:1
