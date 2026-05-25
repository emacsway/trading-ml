(** Outbound [BarsGetAndSubscribe] envelope. Alor correlates the
    stream purely by the client-chosen [guid] (echoed on every data
    frame); the JWT rides in the [token] field, not a header.

    [skipHistory] is set so the subscription delivers only live bars —
    historical backfill is the REST [/md/v2/history] path's job (driven
    by the transport supervisor), keeping the two transports from
    double-delivering the same closed bar. *)

open Core

let subscribe
    ~(cfg : Config.t)
    ~token
    ~guid
    ~(instrument : Instrument.t)
    ~(timeframe : Timeframe.t)
    () : Yojson.Safe.t =
  let from = Int64.of_float (Unix.gettimeofday ()) in
  let group =
    match Routing.instrument_group_of cfg instrument with
    | Some g -> [ ("instrumentGroup", `String g) ]
    | None -> []
  in
  `Assoc
    ([
       ("opcode", `String "BarsGetAndSubscribe");
       ("code", `String (Routing.symbol_of instrument));
       ("exchange", `String (Routing.exchange_of cfg instrument));
       ("tf", `String (Dto.Wire.timeframe_query timeframe));
       ("from", `Intlit (Int64.to_string from));
       ("skipHistory", `Bool true);
       ("format", `String "Simple");
       ("token", `String token);
       ("guid", `String guid);
     ]
    @ group)
