type entry = { submit : string option; cancel : string option }

type t = { table : (int, entry) Hashtbl.t; mutex : Mutex.t }

let create () = { table = Hashtbl.create 64; mutex = Mutex.create () }

let with_lock t f =
  Mutex.lock t.mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock t.mutex) f

let get_entry t placement_id =
  match Hashtbl.find_opt t.table placement_id with
  | Some e -> e
  | None -> { submit = None; cancel = None }

let record_submit t ~placement_id ~correlation_id =
  with_lock t (fun () ->
      let cur = get_entry t placement_id in
      Hashtbl.replace t.table placement_id { cur with submit = Some correlation_id })

let record_cancel t ~placement_id ~correlation_id =
  with_lock t (fun () ->
      let cur = get_entry t placement_id in
      Hashtbl.replace t.table placement_id { cur with cancel = Some correlation_id })

let origin_correlation_id t ~placement_id =
  with_lock t (fun () ->
      match Hashtbl.find_opt t.table placement_id with
      | Some e -> e.submit
      | None -> None)

let cancel_correlation_id t ~placement_id =
  with_lock t (fun () ->
      match Hashtbl.find_opt t.table placement_id with
      | Some e -> e.cancel
      | None -> None)
