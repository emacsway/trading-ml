type 'a t = { mutable handler : ('a -> unit) option }

exception Already_registered

exception No_handler

let create () = { handler = None }

let register_handler t f =
  match t.handler with
  | Some _ -> raise Already_registered
  | None -> t.handler <- Some f

let send t cmd =
  match t.handler with
  | None -> raise No_handler
  | Some f -> f cmd
