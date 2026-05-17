type t =
  | Immediate
  | Twap of Twap_params.t
  | Vwap of Vwap_params.t
  | Pov of Pov_params.t
  | Iceberg of Iceberg_params.t
  | Implementation_shortfall of Implementation_shortfall_params.t
