(** Wire-format command: client submits a new working order to
    paper_broker's matching engine.

    Carries the same shape as the broker BC's local
    [submit_order_command] so the same on-bus channel can be
    handled by either backend depending on deployment. paper_broker
    treats [placement_id] as an opaque round-trip token; it
    never reads or interprets it. *)

include module type of Submit_order_command_t
include module type of Submit_order_command_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t
