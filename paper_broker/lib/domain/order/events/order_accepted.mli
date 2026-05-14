(** Domain Event: paper_broker accepted a freshly-submitted order
    into its working book. Emitted by {!Order.make} on every
    successful construction.

    [reservation_id] is the client's identifier of the order, echoed
    back so the caller can correlate this event with the originating
    submit intent. See {!Values.Reservation_id}. *)

type t = {
  id : string;
  reservation_id : Values.Reservation_id.t;
  instrument : Core.Instrument.t;
  side : Core.Side.t;
  quantity : Decimal.t;
  created_ts : int64;
}
