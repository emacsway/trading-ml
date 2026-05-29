open Core

module Values = Values
(** Re-exports of peer subdirs (see [account/lib/domain/portfolio]).
    Qualified mode collapses the [footprint/] namespace, so peer
    subdirectories are published outside only through here. *)

module Events = Events
module Aggressor = Values.Aggressor
module Print = Values.Print
module Cluster = Values.Cluster
module Bar_boundary = Values.Bar_boundary
module Bar_opened = Events.Bar_opened
module Footprint_completed = Events.Footprint_completed

type status = Forming | Sealed

type t = {
  instrument : Instrument.t;
  boundary : Bar_boundary.t;
  status : status;
  open_ts : int64;
  open_price : Decimal.t;
  close_price : Decimal.t;
  volume : Decimal.t;
  delta : Decimal.t;
  clusters : Cluster.t list;
}

type placement = In_bar | Opens_later | Late

(* Signed contribution of one print to bar delta: Buy adds, Sell
   subtracts, Indeterminate leaves delta untouched. Mirrors
   [Aggressor.sign] in Decimal terms. *)
let delta_step ~aggressor ~size acc =
  match (aggressor : Aggressor.t) with
  | Buy -> Decimal.add acc size
  | Sell -> Decimal.sub acc size
  | Indeterminate -> acc

(* Insert/update the cluster at [price], keeping the list ascending by
   price. New price levels are spliced in at their sorted position. *)
let rec upsert clusters ~price ~aggressor ~size =
  match clusters with
  | [] -> [ Cluster.add (Cluster.empty ~price) ~aggressor ~size ]
  | c :: rest ->
      let cmp = Decimal.compare price c.Cluster.price in
      if cmp = 0 then Cluster.add c ~aggressor ~size :: rest
      else if cmp < 0 then
        Cluster.add (Cluster.empty ~price) ~aggressor ~size :: c :: rest
      else c :: upsert rest ~price ~aggressor ~size

let open_ ~instrument ~boundary ~first =
  let price = first.Print.price
  and size = first.Print.size
  and ts = first.Print.ts
  and aggressor = first.Print.aggressor in
  let open_ts =
    match boundary with
    | Bar_boundary.Time _ -> Bar_boundary.bucket_start boundary ~ts
    | Bar_boundary.Volume _ -> ts
    (* Volume bars have no time grid: the bar opens at the first print's
       own timestamp. *)
  in
  let clusters = [ Cluster.add (Cluster.empty ~price) ~aggressor ~size ] in
  let bar =
    {
      instrument;
      boundary;
      status = Forming;
      open_ts;
      open_price = price;
      close_price = price;
      volume = size;
      delta = delta_step ~aggressor ~size Decimal.zero;
      clusters;
    }
  in
  (bar, { Bar_opened.instrument; boundary; open_ts })

let classify bar p =
  match bar.boundary with
  | Bar_boundary.Time _ ->
      let b = Bar_boundary.bucket_start bar.boundary ~ts:p.Print.ts in
      let cmp = Int64.compare b bar.open_ts in
      if cmp = 0 then In_bar else if cmp > 0 then Opens_later else Late
  | Bar_boundary.Volume cap ->
      (* No-split policy: while the bar has not yet reached [cap] the
         print joins it (even if it tips the total past [cap]); once the
         bar is full the print opens a new one. A [Volume] bar has no
         "Late": its partition follows arrival order, not timestamp, so a
         print never belongs to an already-passed bucket. (Exact-cap
         splitting of the tipping print — Lean's leftover-loop — is the
         documented follow-up; it must split the print's signed volume
         across both bars' clusters while preserving per-bucket
         conservation, hence it is deferred behind this same seam.) *)
      if Decimal.compare bar.volume cap >= 0 then Opens_later else In_bar

let absorb bar p =
  let price = p.Print.price and size = p.Print.size and aggressor = p.Print.aggressor in
  {
    bar with
    close_price = price;
    volume = Decimal.add bar.volume size;
    delta = delta_step ~aggressor ~size bar.delta;
    clusters = upsert bar.clusters ~price ~aggressor ~size;
  }

let seal bar =
  (* high/low and the Point of Control are derived from the per-price
     clusters in a single pass. Clusters are non-empty (open_ seeds the
     first), and ascending, so the lowest price wins POC ties. *)
  let high, low, poc_price, _max_total =
    List.fold_left
      (fun (hi, lo, poc, maxt) c ->
        let price = c.Cluster.price in
        let tot = Cluster.total c in
        let hi = if Decimal.compare price hi > 0 then price else hi in
        let lo = if Decimal.compare price lo < 0 then price else lo in
        let poc, maxt =
          if Decimal.compare tot maxt > 0 then (price, tot) else (poc, maxt)
        in
        (hi, lo, poc, maxt))
      (bar.open_price, bar.open_price, bar.open_price, Decimal.zero)
      bar.clusters
  in
  let sealed = { bar with status = Sealed } in
  let ev =
    {
      Footprint_completed.instrument = bar.instrument;
      boundary = bar.boundary;
      open_ts = bar.open_ts;
      open_price = bar.open_price;
      high;
      low;
      close = bar.close_price;
      volume = bar.volume;
      delta = bar.delta;
      poc_price;
      clusters = bar.clusters;
    }
  in
  (sealed, ev)
