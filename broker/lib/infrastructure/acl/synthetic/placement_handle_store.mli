(** ACL-private mapping {[placement_id → client_order_id]} for
    the Synthetic adapter.

    Synthetic has no real venue and never places real orders; the
    store exists purely so the placement-keyed port surface is
    uniform across adapters. The minted handle is a debug-only
    UUID and is otherwise inert. *)

type t

val create : unit -> t

val record :
  t ->
  placement_id:int ->
  client_order_id:string ->
  [ `Ok | `Already_exists ]
(** Records the linkage produced by a successful submit. Returns
    [`Already_exists] when [placement_id] is already mapped — a
    saga is expected to mint each placement_id once, so a
    collision indicates a replay or upstream bug. *)

val find_client_order_id : t -> placement_id:int -> string option
(** [None] when no placement is recorded — cancel arrived for an
    order this adapter never placed, or its index has been lost. *)

val find_placement_id : t -> client_order_id:string -> int option
(** Reverse lookup, used by listing paths to surface only our
    own placements (foreign orders are filtered out). *)

val all : t -> (int * string) list
(** Snapshot of every recorded linkage. Order unspecified. *)
