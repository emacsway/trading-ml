(** Raw-frame diagnostic for the Finam WS public tape (ADR 0032).

    Unlike {!finam_public_trades_probe}, which routes frames through the
    typed parser and only reacts to Quote / Public_trades (silently
    dropping ERROR / EVENT / unrecognised frames), this probe prints {e
    every} received text frame verbatim and tallies their [type] /
    [subscription_type]. It exists to answer "the typed probe saw nothing
    — what is the socket actually sending?": a rejected subscription
    (ERROR), an expired / over-scoped token, lifecycle acks, or a frame
    shape the parser does not recognise all become visible here.

    Subscribes QUOTES + INSTRUMENT_TRADES for SBER@MISX, drains ~25s.
    Skipped silently when [FINAM_SECRET] is absent. Best during MOEX
    continuous trading.

    {v
      export FINAM_SECRET=<portal secret>
      dune exec broker/test/live_smoke/finam_raw_frames_probe.exe
    v} *)

let pf fmt = Printf.printf (fmt ^^ "\n%!")

let now () =
  let tm = Unix.gmtime (Unix.gettimeofday ()) in
  Printf.sprintf "%02d:%02d:%02d" tm.Unix.tm_hour tm.tm_min tm.tm_sec

let truncate ~max s = if String.length s <= max then s else String.sub s 0 max ^ "…"

(* A coarse (type, subscription_type) label for the tally, read directly
   off the JSON so even frames the typed parser would reject are counted. *)
let label_of s =
  match Yojson.Safe.from_string s with
  | j ->
      let open Yojson.Safe.Util in
      let t =
        match member "type" j with
        | `String x -> x
        | _ -> "?"
      in
      let st =
        match member "subscription_type" j with
        | `String x -> x
        | _ -> "-"
      in
      Printf.sprintf "%s/%s" t st
  | exception _ -> "<non-json>"

let connect ~env ~sw ~cfg =
  let authenticator =
    match Http_transport.load_authenticator () with
    | Ok a -> Some a
    | Error m ->
        pf "[warn] CA load failed (%s) — proceeding without authenticator" m;
        None
  in
  Websocket.Client.connect ~env ~sw ~uri:cfg.Finam.Config.ws_url ?authenticator ()

let run ~env ~clock ~cfg ~token =
  Eio.Switch.run @@ fun sw ->
  let c = connect ~env ~sw ~cfg in
  let instrument = Core.Instrument.of_qualified "SBER@MISX" in
  Websocket.Client.send_text c
    (Yojson.Safe.to_string (Finam.Ws.Requests.Quotes.subscribe ~token [ instrument ]));
  Websocket.Client.send_text c
    (Yojson.Safe.to_string (Finam.Ws.Requests.Public_trades.subscribe ~token instrument));
  pf "[%s] subscribed QUOTES + INSTRUMENT_TRADES SBER@MISX — dumping raw frames 25s..."
    (now ());
  let tally : (string, int) Hashtbl.t = Hashtbl.create 16 in
  let bump k =
    Hashtbl.replace tally k (1 + Option.value ~default:0 (Hashtbl.find_opt tally k))
  in
  let n = ref 0 in
  let handle_text s =
    incr n;
    bump (label_of s);
    (* Print the first frames in near-full, then let the tally carry the
       rest — avoids drowning in a fast quote stream. *)
    if !n <= 40 then pf "[%s] #%-3d %s" (now ()) !n (truncate ~max:400 s)
  in
  (match
     Eio.Time.with_timeout clock 25.0 (fun () ->
         let rec loop () =
           match Websocket.Client.recv c with
           | Text s ->
               handle_text s;
               loop ()
           | Binary _ -> loop ()
           | Close _ -> Ok ()
         in
         try loop () with End_of_file -> Ok ())
   with
  | Ok () -> ()
  | Error `Timeout -> pf "[%s] (25s window elapsed)" (now ()));
  pf "";
  pf "frames received: %d" !n;
  pf "by type/subscription_type:";
  Hashtbl.iter (fun k v -> pf "  %-24s %d" k v) tally;
  if !n = 0 then
    pf
      "=> SOCKET SILENT: connected but zero frames. Token rejected pre-data, wrong WS \
       endpoint, or the subscribe frames never took.";
  Websocket.Client.send_close c ()

let main () =
  match Sys.getenv_opt "FINAM_SECRET" with
  | None | Some "" ->
      pf "[SKIP] FINAM_SECRET not set — export it and re-run.";
      exit 0
  | Some secret ->
      Eio_main.run @@ fun env ->
      Mirage_crypto_rng_unix.use_default ();
      let cfg = Finam.Config.make ~secret () in
      let transport = Http_transport.make_eio ~env in
      let auth = Finam.Auth.make ~secret ~transport ~base:cfg.rest_base in
      let token = Finam.Auth.current auth in
      let clock = Eio.Stdenv.clock env in
      pf "Finam WS endpoint: %s" (Uri.to_string cfg.ws_url);
      pf "auth token acquired: %d chars (jwt)" (String.length token);
      (try run ~env ~clock ~cfg ~token
       with e -> pf "[probe crashed] %s" (Printexc.to_string e));
      pf "DONE."

let () = main ()
