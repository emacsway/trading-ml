type 'a t = { mutable subscribers : (int * ('a -> unit)) list; mutable next_id : int }

type subscription = int

let create () = { subscribers = []; next_id = 0 }

let subscribe t f =
  let id = t.next_id in
  t.next_id <- id + 1;
  t.subscribers <- (id, f) :: t.subscribers;
  id

let unsubscribe t id = t.subscribers <- List.filter (fun (i, _) -> i <> id) t.subscribers

let publish t event =
  (* Fire in subscription order: subscribers list is prepended-to
     in subscribe, so reverse to get FIFO. *)
  List.iter (fun (_, f) -> f event) (List.rev t.subscribers)
