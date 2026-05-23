(** Resilient WebSocket connection with auto-reconnect and heartbeat.

    {1 Reader / consumer split}

    Two fibers, not one. The {b reader} owns {!Client.recv} —
    its only job is to pull frames off the socket as fast as
    they arrive. {!Client.recv} auto-answers RFC 6455 Ping
    frames with Pong inline, so as long as the reader is
    iterating its loop the server's heartbeat is honoured.

    The {b consumer} drains a bounded queue between the two
    fibers and calls [config.on_text]. Anything heavy in
    user-supplied [on_text] (parsing, dispatch, downstream
    integration-event publish, hypothetical synchronous REST)
    runs here — not in the reader — so a slow handler never
    blocks recv, and thus never blocks the auto-pong.

    The queue is bounded; {!Eio.Stream.add} blocks the reader
    if the consumer falls behind by more than [queue_capacity]
    frames. In practice that means at least [queue_capacity ×
    typical-frame-rate] seconds of accumulated lag before the
    reader can stall — far in excess of any server heartbeat
    timeout. A high-watermark warning fires at 80% so a
    deteriorating consumer is observable before the queue
    saturates. *)

let queue_capacity = 1024
let queue_warn_threshold = 819 (* ~80% of capacity *)

type config = {
  label : string;
  ping_interval : float;
  max_backoff : float;
  connect : unit -> Client.t;
  on_text : string -> unit;
  on_disconnect : unit -> unit;
  on_reconnect : unit -> unit;
}

type t = {
  config : config;
  env : Eio_unix.Stdenv.base;
  sw : Eio.Switch.t;
  mutex : Eio.Mutex.t;
  queue : string Eio.Stream.t;
  mutable warned_high_watermark : bool;
  mutable client : Client.t;
  mutable closed : bool;
}

let send t msg = if not t.closed then try Client.send_text t.client msg with _ -> ()

let close t =
  if not t.closed then begin
    t.closed <- true;
    try Client.send_close t.client () with _ -> ()
  end

let is_alive t = not t.closed

(** The reader's only side-effects are: [recv] (which auto-pongs)
    and [Eio.Stream.add]. Both are cheap. If the consumer can't
    keep up, [Eio.Stream.add] blocks here — but the high-water
    threshold logs a warn long before that becomes a real
    problem. *)
let rec spawn_reader t =
  Eio.Fiber.fork_daemon ~sw:t.sw (fun () ->
      (try
         while not t.closed do
           match Client.recv t.client with
           | Text payload ->
               let len = Eio.Stream.length t.queue in
               if len >= queue_warn_threshold && not t.warned_high_watermark then begin
                 t.warned_high_watermark <- true;
                 Log.warn "[%s] consumer queue at %d/%d — slow on_text handler suspected"
                   t.config.label len queue_capacity
               end
               else if len < queue_warn_threshold / 2 && t.warned_high_watermark then
                 t.warned_high_watermark <- false;
               Eio.Stream.add t.queue payload
           | Binary _ | Close _ -> raise Exit
         done
       with End_of_file | Exit -> ());
      if not t.closed then reconnect t;
      `Stop_daemon)

and reconnect t =
  let clock = Eio.Stdenv.clock t.env in
  let backoff = ref 1.0 in
  let connected = ref false in
  (try t.config.on_disconnect () with _ -> ());
  while (not !connected) && not t.closed do
    Log.warn "[%s] disconnected — reconnecting in %.0fs" t.config.label !backoff;
    Eio.Time.sleep clock !backoff;
    if not t.closed then
      begin try
        let c = t.config.connect () in
        Eio.Mutex.use_rw ~protect:true t.mutex (fun () -> t.client <- c);
        spawn_reader t;
        spawn_heartbeat t;
        (try t.config.on_reconnect () with _ -> ());
        Log.info "[%s] reconnected" t.config.label;
        connected := true;
        backoff := 1.0
      with e ->
        Log.warn "[%s] reconnect failed: %s (retry in %.0fs)" t.config.label
          (Printexc.to_string e) !backoff;
        backoff := Float.min (!backoff *. 2.0) t.config.max_backoff
      end
  done

and spawn_heartbeat t =
  let clock = Eio.Stdenv.clock t.env in
  Eio.Fiber.fork_daemon ~sw:t.sw (fun () ->
      (try
         while not t.closed do
           Eio.Time.sleep clock t.config.ping_interval;
           if (not t.closed) && not (Client.is_closed t.client) then
             try Client.send_ping t.client () with _ -> ()
         done
       with _ -> ());
      `Stop_daemon)

(** The consumer's lifetime spans reconnects — the queue and
    the on_text callback are independent of any one socket
    instance. Spawned once at {!create}; it drains forever
    until [t.closed]. Exceptions from user [on_text] are
    swallowed (same policy as before the split). *)
let spawn_consumer t =
  Eio.Fiber.fork_daemon ~sw:t.sw (fun () ->
      (try
         while not t.closed do
           let payload = Eio.Stream.take t.queue in
           try t.config.on_text payload with _ -> ()
         done
       with _ -> ());
      `Stop_daemon)

let create ~env ~sw ~config =
  let client = config.connect () in
  let t =
    {
      config;
      env;
      sw;
      mutex = Eio.Mutex.create ();
      queue = Eio.Stream.create queue_capacity;
      warned_high_watermark = false;
      client;
      closed = false;
    }
  in
  spawn_reader t;
  spawn_consumer t;
  spawn_heartbeat t;
  t
