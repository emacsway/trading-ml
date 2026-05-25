(** ACL-private bridge between the saga's [placement_id : int] and
    Alor's server-assigned order id (a [string]).

    Unlike Finam/BCS — where the adapter mints a [client_order_id] up
    front — Alor assigns the order id only in the placement response
    ([orderNumber]); the store is populated from that response, not
    before the call. The linkage lets cancel / status / fill lookups
    route back to Alor, and lets an inbound fill ([orderno] on a WS /
    REST trade) resolve to its originating placement. Alor handles
    never cross the adapter boundary.

    In-memory for now (parity with the sibling adapters); swapping in a
    restart-durable backend is a single-file change. *)

type t

val create : unit -> t

val record : t -> placement_id:int -> order_id:string -> [ `Ok | `Already_exists ]
(** First write for a [placement_id] wins; a replay returns
    [`Already_exists] without clobbering the existing mapping. *)

val find_order_id : t -> placement_id:int -> string option
val find_placement_id : t -> order_id:string -> int option
