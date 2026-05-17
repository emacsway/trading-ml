(** Execution directive — HOW to execute the trader intent.

    Closed variant: one constructor per strategy kind. Per-strategy
    parameters travel inside the constructor as a dedicated
    [_params] VO (each enforces its own invariants at construction
    so the directive can never carry malformed parameters).

    The directive originates at portfolio_management as part of the
    trader intent and flows through pre_trade_risk unchanged
    (PTR is an approver, not an enricher). Execution_management's
    ACL reads it from the wire; absent → fallback to internal
    [Execution_policy.default] (today: [Immediate]). *)

type t =
  | Immediate
  | Twap of Twap_params.t
  | Vwap of Vwap_params.t
  | Pov of Pov_params.t
  | Iceberg of Iceberg_params.t
  | Implementation_shortfall of Implementation_shortfall_params.t
