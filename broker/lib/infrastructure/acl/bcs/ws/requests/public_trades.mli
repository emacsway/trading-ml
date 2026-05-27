(** WS request encoders for the BCS public-trade (all-trades) channel
    ([dataType:2]). Mirrors {!Candles} minus the timeframe. *)

val subscribe : class_code:string -> ticker:string -> Yojson.Safe.t
val unsubscribe : class_code:string -> ticker:string -> Yojson.Safe.t
