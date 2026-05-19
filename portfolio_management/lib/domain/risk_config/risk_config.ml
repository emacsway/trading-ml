type t = {
  book_id : Common.Book_id.t;
  risk_budget_fraction : Decimal.t;
  limits : Risk.Values.Risk_limits.t;
  construction_source : Common.Source.t;
}

let make ~book_id ~risk_budget_fraction ~limits ~construction_source =
  if Decimal.is_negative risk_budget_fraction
     || Decimal.compare risk_budget_fraction Decimal.one > 0
  then
    invalid_arg
      (Printf.sprintf
         "Risk_config.make: risk_budget_fraction must be in [0, 1] (got %s)"
         (Decimal.to_string risk_budget_fraction));
  { book_id; risk_budget_fraction; limits; construction_source }

let book_id t = t.book_id
let risk_budget_fraction t = t.risk_budget_fraction
let limits t = t.limits
let construction_source t = t.construction_source

let book_equity t ~total_equity =
  Decimal.mul total_equity t.risk_budget_fraction

let authorises t s = Common.Source.equal t.construction_source s
