open Core
module Bar_boundary = Order_flow.Footprint.Values.Bar_boundary

type t = { watched : (string, (string, int) Hashtbl.t) Hashtbl.t; default_token : string }

type watch_outcome = First_for_instrument | Already_watching
type unwatch_outcome = Last_for_instrument | Still_watching

let create ~default_boundary =
  { watched = Hashtbl.create 64; default_token = Bar_boundary.to_token default_boundary }

let watch t ~instrument ~boundary : watch_outcome =
  let sym = Instrument.to_qualified instrument in
  let tok = Bar_boundary.to_token boundary in
  let first_for_instrument = not (Hashtbl.mem t.watched sym) in
  let inner =
    match Hashtbl.find_opt t.watched sym with
    | Some h -> h
    | None ->
        let h = Hashtbl.create 4 in
        Hashtbl.replace t.watched sym h;
        h
  in
  let prev = Option.value ~default:0 (Hashtbl.find_opt inner tok) in
  Hashtbl.replace inner tok (prev + 1);
  if first_for_instrument then First_for_instrument else Already_watching

let unwatch t ~instrument ~boundary : unwatch_outcome =
  let sym = Instrument.to_qualified instrument in
  let tok = Bar_boundary.to_token boundary in
  match Hashtbl.find_opt t.watched sym with
  | None -> Still_watching
  | Some inner ->
      (match Hashtbl.find_opt inner tok with
      | None | Some 1 -> Hashtbl.remove inner tok
      | Some n -> Hashtbl.replace inner tok (n - 1));
      if Hashtbl.length inner = 0 then begin
        Hashtbl.remove t.watched sym;
        Last_for_instrument
      end
      else Still_watching

let boundaries_for t (symbol : string) : Bar_boundary.t list =
  let watched_tokens =
    match Hashtbl.find_opt t.watched symbol with
    | None -> []
    | Some inner ->
        Hashtbl.fold (fun tok n acc -> if n > 0 then tok :: acc else acc) inner []
  in
  t.default_token :: watched_tokens
  |> List.sort_uniq String.compare
  |> List.filter_map (fun tok ->
      match Bar_boundary.of_token tok with
      | b -> Some b
      | exception _ -> None)
