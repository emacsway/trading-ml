(** Domain Event: paper_broker accepted a freshly-submitted order
    into its working book. Emitted by {!Order.make} on every
    successful construction.

    [placement_id] is the client's identifier of the order, echoed
    back so the caller can correlate this event with the originating
    submit intent. See {!Values.Placement_id}. *)

type t = {
  id : string;
  placement_id : Values.Placement_id.t;
  instrument : Core.Instrument.t;
  side : Core.Side.t;
  quantity : Decimal.t;
  created_ts : int64;
}
