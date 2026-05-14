module Order = Paper_broker.Order

type t = { table : (string, Order.t) Hashtbl.t; mutex : Mutex.t }

let create () = { table = Hashtbl.create 64; mutex = Mutex.create () }

let with_lock t f =
  Mutex.lock t.mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock t.mutex) f

let save t (order : Order.t) =
  with_lock t (fun () ->
      if Hashtbl.mem t.table order.id then `Already_exists
      else begin
        Hashtbl.replace t.table order.id order;
        `Ok
      end)

let find t ~id = with_lock t (fun () -> Hashtbl.find_opt t.table id)

let find_active t =
  with_lock t (fun () ->
      Hashtbl.fold
        (fun _ order acc -> if Order.is_terminal order then acc else order :: acc)
        t.table [])

let update t ~id ~f =
  with_lock t (fun () ->
      match Hashtbl.find_opt t.table id with
      | None -> `Not_found
      | Some current ->
          (match f current with
          | `Replace order -> Hashtbl.replace t.table id order
          | `Delete -> Hashtbl.remove t.table id);
          `Updated)

let length t = with_lock t (fun () -> Hashtbl.length t.table)
