(** Multi-channel SSE registry. One subscriber = one SSE connection,
    multiplexes any number of channels:

    - per-key bar feeds (each [(instrument, timeframe)] is independent);
    - global order broadcast.

    A subscriber connects without specifying a chart, then declares
    interest in zero or more bar feeds. The server polls each
    declared upstream once regardless of how many subscribers are
    listening — opening N tabs on the same chart never multiplies
    Finam load. *)

open Core

type event =
  | Bar_updated of Candle.t (* same ts as last cached bar, OHLCV changed *)
  | Bar_closed of Candle.t (* a new bar appeared after the last cached *)

(** Encode to SSE wire format with explicit [event:] field — the
    SSE protocol's native channel mechanism. On the browser side
    [es.addEventListener("bar", ...)] catches only these messages
    and inside the handler the [kind] field discriminates
    [updated] (intra-bar mutation) from [closed] (new bar).

    Both variants share an ordering domain (same instrument,
    same timeframe), so they ride one channel and a single
    sequential consumer on the subscriber preserves their order. *)
let encode_event : event -> string = function
  | Bar_updated c ->
      let j : Yojson.Safe.t =
        `Assoc [ ("kind", `String "updated"); ("candle", Api.candle_json c) ]
      in
      "event: bar\ndata: " ^ Yojson.Safe.to_string j ^ "\n\n"
  | Bar_closed c ->
      let j : Yojson.Safe.t =
        `Assoc [ ("kind", `String "closed"); ("candle", Api.candle_json c) ]
      in
      "event: bar\ndata: " ^ Yojson.Safe.to_string j ^ "\n\n"

type key = Instrument.t * Timeframe.t

module Key = struct
  type t = key
  let compare (i1, t1) (i2, t2) =
    let c = Instrument.compare i1 i2 in
    if c <> 0 then c else compare t1 t2
end

module KMap = Map.Make (Key)
module KSet = Set.Make (Key)

type subscriber = { id : int; queue : string Eio.Stream.t; mutable bar_keys : KSet.t }

type feed = {
  mutable last_candles : Candle.t list;
  mutable cancel : unit -> unit;
      (** True while stale bars are being dropped — log once on
      transition to stale, stay silent until a fresh bar arrives. *)
  mutable stale_warned : bool;
      (** Wall-clock time of the last upstream (WS) push. When WS is
      actively streaming the polling fiber skips its tick, avoiding
      duplicate REST round-trips for data the WS already delivered. *)
  mutable last_upstream_push : float option;
}

type fetch = instrument:Instrument.t -> n:int -> timeframe:Timeframe.t -> Candle.t list

type lifecycle_hook = instrument:Instrument.t -> timeframe:Timeframe.t -> unit

type t = {
  env : Eio_unix.Stdenv.base;
  fetch : fetch;
  on_first : lifecycle_hook;
  on_last : lifecycle_hook;
  mutable feeds : feed KMap.t;
  mutable subscribers : subscriber list;
  mutex : Eio.Mutex.t;
  mutable next_id : int;
  sw : Eio.Switch.t;
}

(** [on_first_subscriber] fires the first time any subscriber declares
    interest in a [(instrument, timeframe)] key — the natural moment
    to forward the subscription to an upstream WS. [on_last_unsubscriber]
    fires when the last interested subscriber drops the key, so the
    upstream subscription can be released. Both default to no-ops,
    keeping [Stream] free of any broker knowledge. *)
let create
    ?(on_first_subscriber : lifecycle_hook = fun ~instrument:_ ~timeframe:_ -> ())
    ?(on_last_unsubscriber : lifecycle_hook = fun ~instrument:_ ~timeframe:_ -> ())
    ~env
    ~sw
    ~fetch
    () =
  {
    env;
    sw;
    fetch;
    on_first = on_first_subscriber;
    on_last = on_last_unsubscriber;
    feeds = KMap.empty;
    subscribers = [];
    mutex = Eio.Mutex.create ();
    next_id = 0;
  }

(** Intra-bar mutation detector: two bars with the same [ts] are
    considered distinct if their OHLC or volume diverge. *)
let same_bar (a : Candle.t) (b : Candle.t) =
  Int64.equal a.ts b.ts && Decimal.equal a.open_ b.open_ && Decimal.equal a.high b.high
  && Decimal.equal a.low b.low && Decimal.equal a.close b.close
  && Decimal.equal a.volume b.volume

let last = function
  | [] -> None
  | l -> Some (List.nth l (List.length l - 1))

(** Compute the ordered events to emit given a fresh snapshot and the
    previously-cached candle list. Emits [Bar_closed] for every bar
    strictly newer than the last cached one (chronologically) and
    [Bar_updated] when the trailing bar kept its timestamp but drifted. *)
let diff_and_emit ~cached ~fresh : event list =
  match (last fresh, last cached) with
  | None, _ -> []
  | Some fl, None -> [ Bar_closed fl ]
  | Some fl, Some cl ->
      let cmp = Int64.compare fl.Candle.ts cl.Candle.ts in
      if cmp > 0 then
        fresh
        |> List.filter (fun c -> Int64.compare c.Candle.ts cl.Candle.ts > 0)
        |> List.map (fun c -> Bar_closed c)
      else if cmp = 0 && not (same_bar fl cl) then [ Bar_updated fl ]
      else []

let poll_interval_seconds (tf : Timeframe.t) : float =
  let s = float_of_int (Timeframe.to_seconds tf) in
  Float.max 2.0 (Float.min 30.0 (s /. 12.0))

(** Snapshot subscribers interested in [key]. Caller must hold [t.mutex]. *)
let subscribers_of_key t key =
  List.filter (fun s -> KSet.mem key s.bar_keys) t.subscribers

let start_poll t (key : key) (feed : feed) =
  let instrument, timeframe = key in
  let interval = poll_interval_seconds timeframe in
  let running = ref true in
  feed.cancel <- (fun () -> running := false);
  let clock = Eio.Stdenv.clock t.env in
  Eio.Fiber.fork_daemon ~sw:t.sw (fun () ->
      (try
         let initial = t.fetch ~instrument ~n:500 ~timeframe in
         Eio.Mutex.use_rw ~protect:true t.mutex (fun () -> feed.last_candles <- initial)
       with e ->
         Log.warn "stream seed %s/%s failed: %s"
           (Instrument.to_qualified instrument)
           (Timeframe.to_string timeframe)
           (Printexc.to_string e));
      while !running do
        Eio.Time.sleep clock interval;
        let ws_fresh =
          match feed.last_upstream_push with
          | None -> false
          | Some ts ->
              (* Skip this poll tick when WS delivered something recently.
             Threshold: 2× the poll interval. If WS goes quiet for
             that long (disconnect, session boundary, broker stall),
             polling resumes automatically. *)
              Eio.Time.now clock -. ts < 2.0 *. interval
        in
        if !running && not ws_fresh then
          try
            let fresh = t.fetch ~instrument ~n:500 ~timeframe in
            let events, subs =
              Eio.Mutex.use_rw ~protect:true t.mutex (fun () ->
                  (* Merge fresh (REST snapshot) with any live WS updates
                  that landed after the last poll. REST can lag WS by
                  a minute or more (Finam caches at minute boundaries),
                  so unconditionally replacing the cache would roll its
                  tail backwards — the next WS candle would then look
                  "newer" than the cache tail and get re-emitted as
                  Bar_closed, producing spurious duplicate-ts events.

                  Strategy: keep every cached bar strictly newer than
                  fresh's tail, append it after the REST history. *)
                  let merged =
                    match (last fresh, last feed.last_candles) with
                    | None, _ -> feed.last_candles (* poll empty → keep cache *)
                    | Some _, None -> fresh
                    | Some fl, Some _ ->
                        let ws_tail =
                          List.filter
                            (fun (c : Candle.t) -> Int64.compare c.ts fl.ts > 0)
                            feed.last_candles
                        in
                        fresh @ ws_tail
                  in
                  let evs = diff_and_emit ~cached:feed.last_candles ~fresh:merged in
                  feed.last_candles <- merged;
                  (evs, subscribers_of_key t key))
            in
            List.iter
              (fun ev ->
                let chunk = encode_event ev in
                List.iter (fun s -> Eio.Stream.add s.queue chunk) subs)
              events
          with e ->
            Log.warn "stream poll %s/%s failed: %s"
              (Instrument.to_qualified instrument)
              (Timeframe.to_string timeframe)
              (Printexc.to_string e)
      done;
      `Stop_daemon)

let connect t : subscriber =
  Eio.Mutex.use_rw ~protect:true t.mutex (fun () ->
      let id = t.next_id in
      t.next_id <- t.next_id + 1;
      let s = { id; queue = Eio.Stream.create 64; bar_keys = KSet.empty } in
      t.subscribers <- s :: t.subscribers;
      s)

(** True iff some other subscriber holds [key]. Caller holds [t.mutex]. *)
let key_has_other_owner t (subscriber : subscriber) key =
  List.exists (fun s -> s.id <> subscriber.id && KSet.mem key s.bar_keys) t.subscribers

let subscribe_bar t (subscriber : subscriber) ~instrument ~timeframe : Candle.t list =
  let key = (instrument, timeframe) in
  let seed, first =
    Eio.Mutex.use_rw ~protect:true t.mutex (fun () ->
        if KSet.mem key subscriber.bar_keys then
          let existing =
            match KMap.find_opt key t.feeds with
            | Some f -> f.last_candles
            | None -> []
          in
          (existing, false)
        else begin
          subscriber.bar_keys <- KSet.add key subscriber.bar_keys;
          match KMap.find_opt key t.feeds with
          | Some f -> (f.last_candles, false)
          | None ->
              let f =
                {
                  last_candles = [];
                  cancel = (fun () -> ());
                  stale_warned = false;
                  last_upstream_push = None;
                }
              in
              t.feeds <- KMap.add key f t.feeds;
              start_poll t key f;
              ([], true)
        end)
  in
  (if first then
     try t.on_first ~instrument ~timeframe
     with e -> Log.warn "stream on_first_subscriber failed: %s" (Printexc.to_string e));
  seed

(** Drop [key] from [subscriber]'s [bar_keys]; if no other subscriber
    holds it, cancel and remove the feed. Returns [true] iff the
    feed was the last and was removed. Caller holds [t.mutex] and
    must ensure [KSet.mem key subscriber.bar_keys]. *)
let drop_bar_key_locked t (subscriber : subscriber) key =
  subscriber.bar_keys <- KSet.remove key subscriber.bar_keys;
  if not (key_has_other_owner t subscriber key) then
    match KMap.find_opt key t.feeds with
    | Some f ->
        f.cancel ();
        t.feeds <- KMap.remove key t.feeds;
        true
    | None -> false
  else false

let unsubscribe_bar t (subscriber : subscriber) ~instrument ~timeframe =
  let key = (instrument, timeframe) in
  let was_last =
    Eio.Mutex.use_rw ~protect:true t.mutex (fun () ->
        if KSet.mem key subscriber.bar_keys then drop_bar_key_locked t subscriber key
        else false)
  in
  if was_last then
    try t.on_last ~instrument ~timeframe
    with e -> Log.warn "stream on_last_unsubscriber failed: %s" (Printexc.to_string e)

let disconnect t (subscriber : subscriber) =
  let lasts =
    Eio.Mutex.use_rw ~protect:true t.mutex (fun () ->
        let keys = KSet.elements subscriber.bar_keys in
        let lasts = List.filter (fun k -> drop_bar_key_locked t subscriber k) keys in
        t.subscribers <- List.filter (fun s -> s.id <> subscriber.id) t.subscribers;
        lasts)
  in
  List.iter
    (fun (instrument, timeframe) ->
      try t.on_last ~instrument ~timeframe
      with e -> Log.warn "stream on_last_unsubscriber failed: %s" (Printexc.to_string e))
    lasts

(** Injection point for alternative upstream sources (WebSocket bridge).
    Updates the cached candle for [(instrument, timeframe)] so the
    polling fiber doesn't re-emit a duplicate, then fans the event out
    to all subscribers that hold this key. No-op if no subscriber
    holds the key (and so the feed doesn't exist). *)
let push_from_upstream t ~instrument ~timeframe (candle : Candle.t) =
  let key = (instrument, timeframe) in
  let now = Eio.Time.now (Eio.Stdenv.clock t.env) in
  let chunk_opt =
    Eio.Mutex.use_rw ~protect:true t.mutex (fun () ->
        match KMap.find_opt key t.feeds with
        | None -> None
        | Some f -> (
            f.last_upstream_push <- Some now;
            (* Monotonicity guard. Upstream brokers occasionally ship a
           stale snapshot right after subscribe (BCS sends the last
           closed candle from the previous session when there's no
           current activity); the chart library [lightweight-charts]
           hard-asserts ascending time order, so out-of-order bars
           break the UI. Drop anything strictly older than the tail
           we already have. Same-ts bars are kept as intra-bar
           updates. *)
            match last f.last_candles with
            | None ->
                (* Cache not seeded yet — the polling fiber's initial fetch
             is still in flight. We can't compare against a tail we
             don't have, and brokers (notably BCS) often push a
             snapshot the instant a subscription is acked; that
             snapshot can legitimately be much older than what
             [/api/candles] already delivered to the subscriber. Drop
             the WS event and wait for polling to seed the cache
             before forwarding anything. *)
                None
            | Some cl when Int64.compare candle.Candle.ts cl.Candle.ts < 0 ->
                if not f.stale_warned then begin
                  f.stale_warned <- true;
                  Log.warn
                    "stream: dropping stale upstream bars for %s/%s (upstream ts=%Ld < \
                     cached tail=%Ld)"
                    (Instrument.to_qualified instrument)
                    (Timeframe.to_string timeframe)
                    candle.ts cl.Candle.ts
                end;
                None
            | last_opt ->
                f.stale_warned <- false;
                let event =
                  match last_opt with
                  | Some cl when Int64.equal cl.Candle.ts candle.ts -> Bar_updated candle
                  | _ -> Bar_closed candle
                in
                let cached =
                  match last_opt with
                  | Some cl when Int64.equal cl.Candle.ts candle.ts -> (
                      match List.rev f.last_candles with
                      | _ :: rest -> List.rev (candle :: rest)
                      | [] -> [ candle ])
                  | _ -> f.last_candles @ [ candle ]
                in
                f.last_candles <- cached;
                Some (encode_event event, subscribers_of_key t key)))
  in
  match chunk_opt with
  | None -> ()
  | Some (chunk, subs) -> List.iter (fun s -> Eio.Stream.add s.queue chunk) subs

(** Broadcast publish for the [order] SSE channel.

    Wraps the caller-supplied JSON in [event: order\n data: ...\n\n]
    framing and pushes the chunk to every connected subscriber's
    queue, regardless of which bar feeds they declared interest in.
    The publisher (in [domain_event_handlers]) is responsible for
    shaping the JSON — typically [{"kind": "placed" | "rejected" | ..., ...}]
    — and for projecting domain events into integration-event DTOs
    before calling here.

    Order events share a single ordering domain on the subscriber
    side (see [docs/architecture/functional-hexagonal.md]); each
    subscriber processes them via a sequential queue under one
    [addEventListener("order", ...)]. *)
let publish_order t (data : Yojson.Safe.t) : unit =
  let chunk = "event: order\ndata: " ^ Yojson.Safe.to_string data ^ "\n\n" in
  let subscribers = Eio.Mutex.use_rw ~protect:true t.mutex (fun () -> t.subscribers) in
  List.iter (fun s -> Eio.Stream.add s.queue chunk) subscribers
