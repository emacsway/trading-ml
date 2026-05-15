type t = int

let of_int n =
  if n <= 0 then invalid_arg (Printf.sprintf "Placement_id.of_int: %d — must be > 0" n);
  n

let to_int n = n
let equal = Int.equal
let compare = Int.compare
