(** Domain Event: a new footprint bar started forming for
    [(instrument, boundary)] at [open_ts] (bucket-aligned unix epoch
    seconds, UTC). Emitted by [Footprint.open_] on the first print of a
    bucket. Past-tense, no suffix, per the project event convention. *)

type t = {
  instrument : Core.Instrument.t;
  boundary : Values.Bar_boundary.t;
  open_ts : int64;
}
