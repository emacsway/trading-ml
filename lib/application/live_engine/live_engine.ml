open Core

type config = {
  broker : Broker.client;
  strategy : Strategies.Strategy.t;
  instrument : Instrument.t;
  initial_cash : Decimal.t;
  limits : Engine.Risk.limits;
  tif : Order.time_in_force;
}

(** Everything the engine needs between bars. Purely functional —
    transitions are pure [state -> state] (plus a broker call on the
    IO edge), which keeps the engine symmetric with [Backtest.run] and
    trivially snapshot-consistent under the mutex. *)
type state = {
  strat : Strategies.Strategy.t;
  position : Decimal.t;
  last_bar_ts : int64;
  seq : int;
  placed : Order.t list;    (** newest first *)
}

type t = {
  cfg : config;
  mutable state : state;    (** sole mutation point *)
  mutex : Mutex.t;
}

let make (cfg : config) : t = {
  cfg;
  state = {
    strat = cfg.strategy;
    position = Decimal.zero;
    last_bar_ts = 0L;
    seq = 0;
    placed = [];
  };
  mutex = Mutex.create ();
}

let with_lock t f =
  Mutex.lock t.mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock t.mutex) f

type intent = {
  side : Side.t;
  quantity : Decimal.t;
  client_order_id : string;
}

(** Client order id format: [eng-<broker>-<strat>-<unix_ts>-<seq>].
    Human-readable for logs; unique under the engine's own mutex;
    stable across broker restarts (seq resets, ts monotonic). *)
let next_cid ~broker_name ~strat_name ~seq =
  Printf.sprintf "eng-%s-%s-%d-%d"
    broker_name strat_name
    (int_of_float (Unix.gettimeofday ()))
    seq

(** Pure: advance strategy state on a new bar. Returns the updated
    state and the raw signal; the caller decides whether to trade. *)
let step ~(config : config) (state : state) (c : Candle.t)
  : state * Signal.t =
  let strat', sig_ = Strategies.Strategy.on_candle
    state.strat config.instrument c in
  { state with strat = strat'; last_bar_ts = c.ts }, sig_

(** Pure: decide whether a signal translates into a tradeable
    side + quantity pair. [Exit_*] close only what we hold; [Enter_*]
    size through the risk gate. *)
let size_for_signal ~(config : config) (state : state)
    (c : Candle.t) (sig_ : Signal.t) : (Side.t * Decimal.t) option =
  let price = c.Candle.close in
  let equity = Decimal.add config.initial_cash
    (Decimal.mul state.position price) in
  let entry_qty side =
    let q = Engine.Risk.size_from_strength
      ~equity ~price ~limits:config.limits
      ~strength:(Float.max 0.1 sig_.strength) in
    if Decimal.is_zero q then None else Some (side, q)
  in
  match sig_.action with
  | Signal.Hold -> None
  | Enter_long  -> entry_qty Side.Buy
  | Enter_short -> entry_qty Side.Sell
  | Exit_long ->
    if Decimal.is_positive state.position
    then Some (Side.Sell, Decimal.abs state.position) else None
  | Exit_short ->
    if Decimal.is_negative state.position
    then Some (Side.Buy, Decimal.abs state.position) else None

(** Pure: consume one [seq] slot to produce an intent (or pass the
    state through unchanged if the signal doesn't warrant action).
    [seq] is bumped regardless of whether the broker subsequently
    accepts the order — that way a rejection-and-retry can never
    reuse the same client_order_id. *)
let intent_of_signal ~(config : config) (state : state)
    (c : Candle.t) (sig_ : Signal.t) : intent option * state =
  match size_for_signal ~config state c sig_ with
  | None -> None, state
  | Some (side, quantity) ->
    let client_order_id = next_cid
      ~broker_name:(Broker.name config.broker)
      ~strat_name:(Strategies.Strategy.name state.strat)
      ~seq:state.seq in
    Some { side; quantity; client_order_id },
    { state with seq = state.seq + 1 }

(** Pure: fold a successful broker response back into the state —
    append to [placed] and update the intent ledger. Position is
    optimistic (see [live_engine.mli] on reconciliation). *)
let after_placed (state : state) ~(side : Side.t) ~(quantity : Decimal.t)
    ~(order : Order.t) : state =
  let position = match side with
    | Buy  -> Decimal.add state.position quantity
    | Sell -> Decimal.sub state.position quantity
  in
  { state with placed = order :: state.placed; position }

let on_bar t (c : Candle.t) =
  with_lock t (fun () ->
    if Int64.compare c.ts t.state.last_bar_ts <= 0 then ()
    else begin
      let s1, sig_ = step ~config:t.cfg t.state c in
      let intent_opt, s2 = intent_of_signal ~config:t.cfg s1 c sig_ in
      t.state <- s2;
      match intent_opt with
      | None -> ()
      | Some intent ->
        try
          let o = Broker.place_order t.cfg.broker
            ~instrument:t.cfg.instrument
            ~side:intent.side ~quantity:intent.quantity
            ~kind:Order.Market ~tif:t.cfg.tif
            ~client_order_id:intent.client_order_id
          in
          t.state <- after_placed t.state
            ~side:intent.side ~quantity:intent.quantity ~order:o;
          Log.info "[engine] %s %s qty=%s cid=%s status=%s"
            (Strategies.Strategy.name t.state.strat)
            (Side.to_string intent.side)
            (Decimal.to_string intent.quantity)
            intent.client_order_id
            (Order.status_to_string o.status)
        with e ->
          Log.warn "[engine] place_order failed (cid=%s): %s"
            intent.client_order_id (Printexc.to_string e)
    end)

let position t = with_lock t (fun () -> t.state.position)
let placed t = with_lock t (fun () -> List.rev t.state.placed)
