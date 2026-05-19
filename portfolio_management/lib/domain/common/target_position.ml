open Core

type t = {
  book_id : Book_id.t;
  instrument : Instrument.t;
  target_qty : Decimal.t;
  coupling : Coupling.t option;
}

let coupling_equal a b =
  match (a, b) with
  | None, None -> true
  | Some x, Some y -> Coupling.equal x y
  | _ -> false

let equal p q =
  Book_id.equal p.book_id q.book_id
  && Instrument.equal p.instrument q.instrument
  && Decimal.equal p.target_qty q.target_qty
  && coupling_equal p.coupling q.coupling
