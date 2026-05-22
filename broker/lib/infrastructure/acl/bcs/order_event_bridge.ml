let start
    ~(env : Eio_unix.Stdenv.base)
    ~(sw : Eio.Switch.t)
    ~(cfg : Config.t)
    ~(auth : Auth.t)
    ~(on_event : Ws.Events.Order_event.t -> unit)
    ~(on_disconnect : unit -> unit)
    ~(on_reconnect : unit -> unit) : unit =
  let authenticator =
    match Http_transport.load_authenticator () with
    | Ok a -> Some a
    | Error m ->
        Log.warn "[bcs order ws] CA load failed: %s" m;
        None
  in
  let config : Websocket.Resilient.config =
    {
      label = "bcs order ws";
      ping_interval = 30.0;
      max_backoff = 60.0;
      connect =
        (fun () ->
          let extra_headers = [ ("Authorization", "Bearer " ^ Auth.current auth) ] in
          Websocket.Client.connect ~env ~sw ~uri:cfg.Config.ws_orders_execution_url
            ~extra_headers ?authenticator ());
      on_text =
        (fun payload ->
          try
            let j = Yojson.Safe.from_string payload in
            match Ws.Events.Order_event.parse j with
            | Some ev -> on_event ev
            | None -> Log.warn "[bcs order ws] unparseable order event: %s" payload
          with e ->
            Log.warn "[bcs order ws] decode failed: %s raw: %s" (Printexc.to_string e)
              payload);
      on_disconnect;
      on_reconnect;
    }
  in
  let _ : Websocket.Resilient.t = Websocket.Resilient.create ~env ~sw ~config in
  ()
