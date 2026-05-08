type t = string

let of_string raw =
  if raw = "" then invalid_arg "Correlation_id.of_string: empty" else raw

(* RNG initialised once on first call. UUIDv4 is the canonical form for
   an opaque saga-key — no embedded timing means callers cannot
   accidentally treat the id as a timestamp. *)
let rng = lazy (Random.State.make_self_init ())

let generate () = Uuidm.to_string (Uuidm.v4_gen (Lazy.force rng) ())

let to_string s = s
let equal = String.equal
let compare = String.compare
let hash = Hashtbl.hash
