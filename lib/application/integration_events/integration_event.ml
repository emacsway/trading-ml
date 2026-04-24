(** Contract implemented by each [*_integration_event.ml] in
    this library. Shape-identical to {!Queries.View_model.S} —
    both are outbound primitive-typed projections of the domain
    layer. The semantic difference:

    - View models project {i state} — current snapshot of an
      aggregate / entity for read endpoints (GET /api/orders).
    - Integration events project {i happenings} — past-tense
      facts for outbound messaging (HTTP response body for the
      originating command, websocket fan-out, message bus,
      audit log).

    Kept as two separate libraries rather than one so a future
    reader can tell from the directory name whether a type is a
    state projection or an event projection. *)

module type S = sig
  type t
  (** DTO: primitive-typed, serializable. *)

  type domain
  (** Corresponding domain event. *)

  val yojson_of_t : t -> Yojson.Safe.t
  val t_of_yojson : Yojson.Safe.t -> t

  val of_domain : domain -> t
  (** Total projection. Domain events are always well-formed by
      construction, so this can't fail. *)
end
