(** Separate JSON encoding so [Decimal.mli] stays free of external-module
    references and remains Gospel-checkable. *)

let yojson_of_t x : Yojson.Safe.t = `String (Decimal.to_string x)

let t_of_yojson : Yojson.Safe.t -> Decimal.t = function
  | `String s -> Decimal.of_string s
  | `Int n -> Decimal.of_int n
  | `Float f -> Decimal.of_float f
  | `Intlit s -> Decimal.of_string s
  | j -> invalid_arg ("Decimal.t_of_yojson: " ^ Yojson.Safe.to_string j)
