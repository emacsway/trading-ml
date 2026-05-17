(** pre_trade_risk BC composition root. Allocates per-book Risk_view
    aggregates, hosts the portfolio-wide drawdown circuit
    (kill_switch) and the intake-throttle (rate_limit), builds
    command-dispatch ports, subscribes to the upstream
    integration-event topics, and exposes the HTTP handler. *)

type t = { http_handler : Inbound_http.Route.handler }

type config = {
  initial_equity : Decimal.t;
      (** Feeds {!Pre_trade_risk.Risk_limits.default} and seeds the
          kill_switch's [peak_equity]. *)
  max_drawdown_pct : float;
      (** Kill-switch trigger as fraction in [0,1]. [0.0] disables. *)
  rate_limit : (int * float) option;
      (** [Some (max_orders, window_seconds)] caps the intake rate;
          [None] disables. Defends against runaway strategies. *)
}

val build : bus:Bus.bus -> now:(unit -> int64) -> config:config -> t
