type t = { ts : int64; volume : Decimal.t }

let make ~ts ~volume =
  if Decimal.compare volume Decimal.zero < 0 then
    invalid_arg "Volume_bar.make: volume must be non-negative";
  { ts; volume }
