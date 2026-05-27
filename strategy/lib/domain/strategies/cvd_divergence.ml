type params = { lookback : int }
type position = Flat | Long | Short
type sample = { high : float; low : float; cvd : float }

type state = {
  params : params;
  cvd : float;
  history : sample list; (* most-recent-first, capped at [lookback] *)
  position : position;
}

let name = "FootprintCVDDivergence"
let default_params = { lookback = 20 }

let init p =
  if p.lookback < 2 then invalid_arg "Cvd_divergence: lookback must be >= 2";
  { params = p; cvd = 0.0; history = []; position = Flat }

let f = Decimal.to_float

(* Keep the first [n] of a most-recent-first list. *)
let rec take n = function
  | x :: xs when n > 0 -> x :: take (n - 1) xs
  | _ -> []

let on_footprint st instrument (b : Footprint_bar.t) =
  let cvd = st.cvd +. f b.Footprint_bar.delta in
  let cur = { high = f b.Footprint_bar.high; low = f b.Footprint_bar.low; cvd } in
  let prior = st.history in
  let action, position, reason =
    if List.length prior < st.params.lookback - 1 then (Signal.Hold, st.position, "")
    else
      let max_high =
        List.fold_left (fun m (s : sample) -> Float.max m s.high) neg_infinity prior
      in
      let max_cvd =
        List.fold_left (fun m (s : sample) -> Float.max m s.cvd) neg_infinity prior
      in
      let min_low =
        List.fold_left (fun m (s : sample) -> Float.min m s.low) infinity prior
      in
      let min_cvd =
        List.fold_left (fun m (s : sample) -> Float.min m s.cvd) infinity prior
      in
      let bearish = cur.high > max_high && cur.cvd <= max_cvd in
      let bullish = cur.low < min_low && cur.cvd >= min_cvd in
      match st.position with
      | Flat when bullish ->
          (Signal.Enter_long, Long, Printf.sprintf "bullish CVD divergence (cvd=%.1f)" cvd)
      | Flat when bearish ->
          ( Signal.Enter_short,
            Short,
            Printf.sprintf "bearish CVD divergence (cvd=%.1f)" cvd )
      | Long when bearish -> (Signal.Exit_long, Flat, "bearish CVD divergence while long")
      | Short when bullish ->
          (Signal.Exit_short, Flat, "bullish CVD divergence while short")
      | _ -> (Signal.Hold, st.position, "")
  in
  let history = take st.params.lookback (cur :: prior) in
  let strength =
    match action with
    | Signal.Hold -> 0.0
    | _ -> 1.0
  in
  let sig_ =
    {
      Signal.ts = b.Footprint_bar.ts;
      instrument;
      action;
      strength;
      stop_loss = None;
      take_profit = None;
      reason;
    }
  in
  ({ st with cvd; history; position }, sig_)
