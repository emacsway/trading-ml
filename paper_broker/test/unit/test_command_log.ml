(** In-memory {!Paper_broker_store.Order_command_log.S} implementation
    for sociable tests. Single-threaded; no locking. *)

type entry = { submit : string option; cancel : string option }
type t = (string, entry) Hashtbl.t

let create () : t = Hashtbl.create 8

let get_entry t aggregate_id =
  match Hashtbl.find_opt t aggregate_id with
  | Some e -> e
  | None -> { submit = None; cancel = None }

let record_submit t ~aggregate_id ~correlation_id =
  let cur = get_entry t aggregate_id in
  Hashtbl.replace t aggregate_id { cur with submit = Some correlation_id }

let record_cancel t ~aggregate_id ~correlation_id =
  let cur = get_entry t aggregate_id in
  Hashtbl.replace t aggregate_id { cur with cancel = Some correlation_id }

let origin_correlation_id t ~aggregate_id =
  match Hashtbl.find_opt t aggregate_id with
  | Some e -> e.submit
  | None -> None

let cancel_correlation_id t ~aggregate_id =
  match Hashtbl.find_opt t aggregate_id with
  | Some e -> e.cancel
  | None -> None
