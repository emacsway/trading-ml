type t = string

let make ?(source = "") (occurred_at : int64) : t =
  Printf.sprintf "%Ld:%s" occurred_at source

let to_string t = t
let equal = String.equal
let compare = String.compare
