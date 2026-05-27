type t = { price : Decimal.t; size : Decimal.t; ts : int64; aggressor : Aggressor.t }

let make ~price ~size ~ts ~aggressor =
  if not (Decimal.is_positive size) then invalid_arg "Print.make: size must be positive";
  { price; size; ts; aggressor }
