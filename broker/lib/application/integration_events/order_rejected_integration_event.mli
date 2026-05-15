(** Integration event: the broker reached the upstream venue and
    explicitly refused the submission — wire validation failed,
    account state forbade the order, instrument not tradeable, etc.

    [placement_id] echoes the saga key supplied in
    {!Submit_order_command.t}; Account's compensation subscriber
    uses it to call {!Account_release_command} and roll back the
    earmarked cash / quantity.

    No [client_order_id] field — there is no order to refer to
    (the broker did not create one). UI tracks the request via
    [placement_id] only for this terminal outcome. *)

type t = { correlation_id : string; placement_id : int; reason : string }
[@@deriving yojson]
