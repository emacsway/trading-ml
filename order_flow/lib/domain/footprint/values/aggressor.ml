type t = Buy | Sell | Indeterminate

let to_string = function
  | Buy -> "BUY"
  | Sell -> "SELL"
  | Indeterminate -> "INDETERMINATE"

let of_string = function
  | "BUY" | "buy" | "Buy" -> Buy
  | "SELL" | "sell" | "Sell" -> Sell
  | "UNSPECIFIED" | "unspecified" | "NONE" | "none" | "" -> Indeterminate
  | s -> invalid_arg ("Aggressor.of_string: " ^ s)

let sign = function
  | Buy -> 1
  | Sell -> -1
  | Indeterminate -> 0
