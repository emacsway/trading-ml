(** Domain Event: a working order was cancelled before reaching a
    fill-terminal status. Emitted by {!Order.cancel} on a successful
    transition out of [New] or [Partially_filled].

    [placement_id] is the client's identifier of the order. *)

type t = {
  id : string;
  placement_id : Values.Placement_id.t;
  instrument : Core.Instrument.t;
  cancelled_ts : int64;
}
