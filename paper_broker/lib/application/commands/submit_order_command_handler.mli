(** Command handler for {!Submit_order_command.t}.

    Owns the entire submission step: parse the wire-format command,
    validate the primitives back into domain VOs (side, instrument,
    decimal qty, kind variant, tif, placement_id), allocate a
    fresh order id via the injected port, build the
    {!Paper_broker.Order.t} aggregate via {!Paper_broker.Order.make}
    with [placement_id] as the client-supplied natural identifier,
    and persist via the {!Paper_broker_store.Order_store.S} port.

    Returns the saved {!Paper_broker.Order.t} plus the
    {!Paper_broker.Order.Events.Order_accepted.t} domain event.
    Recording the submit-correlation in the
    {!Paper_broker_store.Order_command_log.S} is the enclosing
    workflow's job (the handler is store-only). *)

(** {1 Validation errors} *)

type validation_error =
  | Invalid_symbol of string
  | Invalid_side of string
  | Invalid_quantity_format of string
  | Non_positive_quantity of string
  | Non_positive_placement_id of int
  | Invalid_kind of string
  | Invalid_kind_price_format of { field : string; value : string }
  | Non_positive_kind_price of { field : string; value : string }
  | Missing_kind_price of { kind : string; field : string }
  | Invalid_tif of string

val validation_error_to_string : validation_error -> string

(** {1 Validated form} *)

type validated_submit_order_command = {
  correlation_id : string;
  placement_id : Paper_broker.Order.Values.Placement_id.t;
  instrument : Core.Instrument.t;
  side : Core.Side.t;
  quantity : Decimal.t;
  kind : Paper_broker.Order.Values.Order_kind.t;
  tif : Paper_broker.Order.Values.Time_in_force.t;
}
(** Post-parse intermediate form: wire primitives lifted into
    domain types but the order has not yet been built nor
    persisted. *)

(** {1 Outcome} *)

type handle_error = Validation of validation_error

module type Store = Paper_broker_store.Order_store.S

val handle :
  store:(module Store with type t = 'store) ->
  store_handle:'store ->
  next_order_id:(unit -> string) ->
  now_ts:(unit -> int64) ->
  placed_after_ts:(Core.Instrument.t -> int64) ->
  Submit_order_command.t ->
  (Paper_broker.Order.t * Paper_broker.Order.Events.Order_accepted.t, handle_error) Rop.t
(** Parse the wire-format command, build and persist the order,
    and yield the resulting domain event. Does not publish any
    integration event and does not write to the correlation log —
    those are the {!Submit_order_command_workflow.execute}
    pipeline's job.

    Ports:
    - [next_order_id] — server-side surrogate id generator. Must
      be unique against the store; a collision raises
      [Invalid_argument].
    - [now_ts] — current wall-clock ms-precision timestamp.
    - [placed_after_ts] — instrument-specific "floor" timestamp
      (no-lookahead). Typically the last seen bar timestamp for
      that instrument. *)
