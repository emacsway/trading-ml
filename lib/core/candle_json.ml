(** JSON encoding kept separate so [Candle.mli] remains Gospel-checkable. *)

let yojson_of_t (c : Candle.t) : Yojson.Safe.t =
  `Assoc [
    "ts", `Intlit (Int64.to_string c.Candle.ts);
    "open", Decimal_json.yojson_of_t c.open_;
    "high", Decimal_json.yojson_of_t c.high;
    "low", Decimal_json.yojson_of_t c.low;
    "close", Decimal_json.yojson_of_t c.close;
    "volume", Decimal_json.yojson_of_t c.volume;
  ]

let t_of_yojson (j : Yojson.Safe.t) : Candle.t =
  let open Yojson.Safe.Util in
  let ts = match member "ts" j with
    | `Int n -> Int64.of_int n
    | `Intlit s -> Int64.of_string s
    | `String s -> Int64.of_string s
    | _ -> invalid_arg "Candle.ts"
  in
  let d k = Decimal_json.t_of_yojson (member k j) in
  Candle.make ~ts
    ~open_:(d "open") ~high:(d "high") ~low:(d "low")
    ~close:(d "close") ~volume:(d "volume")
