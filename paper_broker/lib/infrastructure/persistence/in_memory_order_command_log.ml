type entry = { submit : string option; cancel : string option }
(** Per-aggregate slot capturing the [correlation_id] of the most
    recent {!record_submit} and the most recent {!record_cancel}.
    Two slots in one record (rather than a list) — enough for the
    current consumers ({!origin_correlation_id} reads submit), and
    keeps the structure simple until a proper event log lands. *)

type t = { table : (string, entry) Hashtbl.t; mutex : Mutex.t }

let create () = { table = Hashtbl.create 64; mutex = Mutex.create () }

let with_lock t f =
  Mutex.lock t.mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock t.mutex) f

let get_entry t aggregate_id =
  match Hashtbl.find_opt t.table aggregate_id with
  | Some e -> e
  | None -> { submit = None; cancel = None }

let record_submit t ~aggregate_id ~correlation_id =
  with_lock t (fun () ->
      let cur = get_entry t aggregate_id in
      Hashtbl.replace t.table aggregate_id { cur with submit = Some correlation_id })

let record_cancel t ~aggregate_id ~correlation_id =
  with_lock t (fun () ->
      let cur = get_entry t aggregate_id in
      Hashtbl.replace t.table aggregate_id { cur with cancel = Some correlation_id })

let origin_correlation_id t ~aggregate_id =
  with_lock t (fun () ->
      match Hashtbl.find_opt t.table aggregate_id with
      | Some e -> e.submit
      | None -> None)

let cancel_correlation_id t ~aggregate_id =
  with_lock t (fun () ->
      match Hashtbl.find_opt t.table aggregate_id with
      | Some e -> e.cancel
      | None -> None)
