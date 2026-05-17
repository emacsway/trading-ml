(** VWAP — Volume-Weighted Average Price — strategy.

    Same time grid as TWAP ([n_slices] over [window_seconds] from
    [start_at]) but slice quantities follow the supplied normalised
    [volume_profile]. The first [n-1] slices carry
    [round(total × weight_i)] each; the final slice carries the
    residue [total − Σ_first_n-1] so [Σ slice_qty = total_quantity]
    holds exactly.

    Behaviour matches TWAP: one slice per tick at the scheduled
    instant; Volume_bar / Price_quote inputs ignored (those
    eventually drive a separate dynamic-VWAP refinement);
    rejection / unreachable / cancelled → terminal Failed. *)

(*@ function dec_raw (d : Decimal.t) : integer *)

type state

val init :
  intent:Values.Trade_intent.t ->
  params:Values.Vwap_params.t ->
  now:int64 ->
  state * Decision.t
(*@ s, d = init ~intent ~params ~now
    requires dec_raw intent.Values.Trade_intent.total_quantity > 0
    requires params.Values.Vwap_params.n_slices > 0
    ensures d.Decision.submit = []
    ensures d.Decision.terminal = Decision.Continue *)

val on_event : state -> Input.t -> now:int64 -> state * Decision.t

val is_complete : state -> bool
