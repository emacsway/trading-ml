(** Trading-system runtime configuration.

    Re-exports the atdgen-generated record + JSON projections
    from [shared/contracts/config/trading_config.atd]. Every
    field at every nesting level is [option]; the layered
    loader fills in defaults from [config/default.config.json]
    before per-deployment / env / CLI overrides.

    Defaults living in JSON (not in [~default] ATD annotations)
    is a deliberate choice: changing a default is then a config
    edit, not a code edit requiring recompile.

    Adding a new field still requires recompile (strongly-typed
    OCaml). That cost is unavoidable; the design merely confines
    recompile to schema evolution, not to value tuning. *)

include module type of struct
  include Trading_config_t
  include Trading_config_j
end

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

module Loader : module type of Loader
module Merger : module type of Merger
