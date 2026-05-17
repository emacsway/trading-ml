(** Iceberg — Show-and-Refill — parameters.

    Shows only [visible_qty] to the market at a time; on each fill
    of the visible slice, refills with another [visible_qty]
    (capped by remaining) until the total intent is exhausted.

    Invariants:
    - [visible_qty > 0]. *)

(*@ function dec_raw (d : Decimal.t) : integer *)

type t = private { visible_qty : Decimal.t }

val make : visible_qty:Decimal.t -> t
(*@ r = make ~visible_qty
    requires dec_raw visible_qty > 0
    ensures dec_raw r.visible_qty = dec_raw visible_qty *)
