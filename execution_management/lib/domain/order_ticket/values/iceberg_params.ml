type t = { visible_qty : Decimal.t }

let make ~visible_qty =
  if Decimal.compare visible_qty Decimal.zero <= 0 then
    invalid_arg "Iceberg_params.make: visible_qty must be positive";
  { visible_qty }
