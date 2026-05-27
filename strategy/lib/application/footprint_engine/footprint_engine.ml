open Core

type config = {
  strategy : Strategies.Footprint_strategy.t;
  instrument : Instrument.t;
  strategy_id : string;
}

module Signal_detected = Strategy_integration_events.Signal_detected_integration_event

type t = {
  mutable strat : Strategies.Footprint_strategy.t;
  cfg : config;
  publish_signal_detected : Signal_detected.t -> unit;
  mutable last_ts : int64;
  mu : Mutex.t;
}

let make ~(config : config) ~publish_signal_detected =
  {
    strat = config.strategy;
    cfg = config;
    publish_signal_detected;
    last_ts = Int64.min_int;
    mu = Mutex.create ();
  }

let with_lock t f =
  Mutex.lock t.mu;
  Fun.protect ~finally:(fun () -> Mutex.unlock t.mu) f

let on_footprint t (b : Footprint_bar.t) =
  with_lock t (fun () ->
      if Int64.compare b.Footprint_bar.ts t.last_ts <= 0 then ()
      else begin
        t.last_ts <- b.Footprint_bar.ts;
        let strat', sig_ =
          Strategies.Footprint_strategy.on_footprint t.strat t.cfg.instrument b
        in
        t.strat <- strat';
        match sig_.action with
        | Hold -> ()
        | _ ->
            let ie =
              Signal_detected.of_domain ~strategy_id:t.cfg.strategy_id
                ~price:b.Footprint_bar.close sig_
            in
            t.publish_signal_detected ie
      end)

let run t ~source = Pipe.Stream.iter (on_footprint t) source
