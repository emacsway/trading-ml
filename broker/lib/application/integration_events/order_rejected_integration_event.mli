(** Integration event: the broker reached the upstream venue and
    explicitly refused the submission — wire validation failed,
    account state forbade the order, instrument not tradeable, etc.

    [placement_id] echoes the saga key supplied in
    {!Submit_order_command.t}; Account's compensation subscriber
    uses it to call {!Account_release_command} and roll back the
    earmarked cash / quantity.

    No [client_order_id] field — there is no order to refer to
    (the broker did not create one). UI tracks the request via
    [placement_id] only for this terminal outcome.

    The wire shape is generated from
    [shared/contracts/broker/integration_events/order_rejected_integration_event.atd]
    via atdgen; this module re-exports the generated types and
    codecs and adds [yojson_of_t] / [t_of_yojson] aliases for
    backward compatibility with [@@deriving yojson]-style
    callers. *)

include module type of Order_rejected_integration_event_t

include module type of Order_rejected_integration_event_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
