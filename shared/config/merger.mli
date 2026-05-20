(** Layered-config merge combinator.

    [merge base overlay] returns a [Trading_config.t] where each
    field is taken from [overlay] when present, falling back to
    [base] otherwise. The "later wins" semantics extends
    recursively into nested records (e.g. [server.port] is
    chosen field-by-field, not record-by-record).

    Variant-typed fields (broker selection) are taken whole:
    [overlay.broker = Some (Finam ...)] replaces
    [base.broker = Some (Bcs ...)] in its entirety. Per-field
    overlay on variant payloads would require structural
    matching the variants are deliberately avoiding.

    {b Pure}: same inputs → same output, no I/O. The four-layer
    loader composes [merge] four times. *)

val merge : Trading_config_t.t -> Trading_config_t.t -> Trading_config_t.t
(** Takes raw [Trading_config_t.t] from the atdgen-generated
    module to keep submodule deps below the library's main
    module. Callers from outside the library see this as
    [Trading_config.t] via the public alias. *)
