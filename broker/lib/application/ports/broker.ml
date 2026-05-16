(** Broker abstraction — the order-routing port of the broker
    BC, expressed in our model's vocabulary only. Concrete
    integrations (Finam, BCS, Synthetic) implement [S] in their
    own library; the application talks to them through an
    existential [client] wrapper so adding a new broker is a new
    module, not a new branch in every switch.

    {b Order identity.} The only identity carried at the port
    boundary is [placement_id : int] — the cross-BC saga key
    minted by Account at reservation time and echoed through
    Submit. Venue-native handles ([client_order_id], server-side
    ids, exec ids) are concerns of each ACL adapter: every adapter
    holds its own private [placement_id ↦ native_handle] store
    (see e.g. {!Bcs.Placement_handle_store}) and never surfaces
    those handles across the port.

    {b Legacy.} The [client_order_id]-keyed methods below are
    retained for the venue-keyed HTTP debug routes
    ([GET / DELETE /api/orders/<cid>]); they will be removed
    alongside those routes. New callers must use the placement-
    keyed methods. *)

open Core

module type S = sig
  type t

  val name : string
  (** Identifier used on the CLI (e.g. "finam", "bcs") and in logs. *)

  val bars :
    t -> n:int -> instrument:Instrument.t -> timeframe:Timeframe.t -> Candle.t list

  val venues : t -> Mic.t list

  (** {1 Placement-keyed API (architectural target)} *)

  val place_order_by_placement_id :
    t ->
    placement_id:int ->
    instrument:Instrument.t ->
    side:Side.t ->
    quantity:Decimal.t ->
    kind:Order.kind ->
    tif:Order.time_in_force ->
    Order_view_model.t
  (** Submit a new order under the saga's [placement_id]. The
      adapter mints whatever native handle the venue requires,
      records the linkage in its private placement-handle store,
      and projects the venue's response onto the wire view model.
      Returns the projection at submission time — [status] is
      typically [NEW] / [PENDING_NEW], but may already reflect a
      partial or full fill on aggressive orders. *)

  val cancel_order_by_placement_id :
    t -> placement_id:int -> Order_view_model.t option
  (** Resolve [placement_id] to the adapter's native handle, call
      the venue's cancel, project the response. [None] when no
      placement is recorded under this id (cancel arrived for an
      order this adapter never placed, or its index has been
      lost). *)

  val get_order_by_placement_id :
    t -> placement_id:int -> Order_view_model.t option
  (** Snapshot of a single placement's state. [None] when no
      placement is recorded under this id. *)

  val get_executions_by_placement_id :
    t -> placement_id:int -> Execution_view_model.t list
  (** Per-execution detail for a placement. Empty list when the
      order has no fills yet or no placement is recorded. *)

  (** {1 Legacy venue-keyed API (HTTP debug surface; deprecated)} *)

  val place_order :
    t ->
    instrument:Instrument.t ->
    side:Side.t ->
    quantity:Decimal.t ->
    kind:Order.kind ->
    tif:Order.time_in_force ->
    client_order_id:string ->
    Order.t

  val get_orders : t -> Order.t list

  val get_order : t -> client_order_id:string -> Order.t

  val cancel_order : t -> client_order_id:string -> Order.t

  val get_executions : t -> client_order_id:string -> Order.execution list

  val generate_client_order_id : t -> string
end

type client = E : (module S with type t = 't) * 't -> client

let make (type a) (module M : S with type t = a) (x : a) : client = E ((module M), x)

let name (E ((module M), _)) = M.name

let bars (E ((module M), t)) ~n ~instrument ~timeframe =
  M.bars t ~n ~instrument ~timeframe

let venues (E ((module M), t)) = M.venues t

let place_order_by_placement_id
    (E ((module M), t)) ~placement_id ~instrument ~side ~quantity ~kind ~tif =
  M.place_order_by_placement_id t ~placement_id ~instrument ~side ~quantity ~kind ~tif

let cancel_order_by_placement_id (E ((module M), t)) ~placement_id =
  M.cancel_order_by_placement_id t ~placement_id

let get_order_by_placement_id (E ((module M), t)) ~placement_id =
  M.get_order_by_placement_id t ~placement_id

let get_executions_by_placement_id (E ((module M), t)) ~placement_id =
  M.get_executions_by_placement_id t ~placement_id

let place_order
    (E ((module M), t))
    ~instrument
    ~side
    ~quantity
    ~kind
    ~tif
    ~client_order_id =
  M.place_order t ~instrument ~side ~quantity ~kind ~tif ~client_order_id

let get_orders (E ((module M), t)) = M.get_orders t

let get_order (E ((module M), t)) ~client_order_id = M.get_order t ~client_order_id

let cancel_order (E ((module M), t)) ~client_order_id = M.cancel_order t ~client_order_id

let get_executions (E ((module M), t)) ~client_order_id =
  M.get_executions t ~client_order_id

let generate_client_order_id (E ((module M), t)) = M.generate_client_order_id t
