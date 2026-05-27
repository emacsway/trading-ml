type t = {
  price : Decimal.t;
  buy_volume : Decimal.t;
  sell_volume : Decimal.t;
  indeterminate_volume : Decimal.t;
}

let empty ~price =
  {
    price;
    buy_volume = Decimal.zero;
    sell_volume = Decimal.zero;
    indeterminate_volume = Decimal.zero;
  }

let add c ~aggressor ~size =
  match (aggressor : Aggressor.t) with
  | Buy -> { c with buy_volume = Decimal.add c.buy_volume size }
  | Sell -> { c with sell_volume = Decimal.add c.sell_volume size }
  | Indeterminate ->
      { c with indeterminate_volume = Decimal.add c.indeterminate_volume size }

let total c = Decimal.add (Decimal.add c.buy_volume c.sell_volume) c.indeterminate_volume

let delta c = Decimal.sub c.buy_volume c.sell_volume
