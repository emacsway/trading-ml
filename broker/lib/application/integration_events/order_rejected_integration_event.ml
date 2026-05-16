include Order_rejected_integration_event_t
include Order_rejected_integration_event_j

(** Backward-compatible aliases for [@@deriving yojson]-style
    callers. atdgen emits [string_of_t] / [t_of_string]; the
    rest of the codebase still expects [yojson_of_t] /
    [t_of_yojson] against [Yojson.Safe.t]. The string round-trip
    is the simplest bridge that keeps both APIs available. *)
let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)

let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)
