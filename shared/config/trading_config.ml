include Trading_config_t
include Trading_config_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

(* Re-export submodules so external callers see them as
   [Trading_config.Loader] / [Trading_config.Merger]. *)
module Loader = Loader
module Merger = Merger
