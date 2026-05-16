(** Integration event: a strategy detected an actionable signal on a
    bar close.

    Carries a directional forecast — [UP] / [DOWN] / [FLAT] — together
    with a normalised [strength] in [0.0; 1.0]. The forecast is a
    declarative alpha-mind: [UP] / [DOWN] state the strategy's current
    directional opinion, [FLAT] states the absence of one. Bracket
    exits ({!Common.Signal.Exit_long} / {!Common.Signal.Exit_short}),
    fired when a TP / SL / timeout barrier resolves a previously-opened
    position, are alpha-expiry events: they project to [FLAT] (the
    strategy withdraws its view), with the outcome recorded verbatim
    in [reason] for downstream telemetry. The consumer (e.g. Portfolio
    Management's alpha-driven construction policy) translates [FLAT]
    into a zero target on the corresponding book; cancelling in-flight
    orders against the obsolete target is execution-layer work, not
    alpha's.

    DTO-shaped: primitives + nested view model, no domain values.
    Wire format generated from the atd contract. *)

include module type of Signal_detected_integration_event_t
include module type of Signal_detected_integration_event_j with type t := t

val yojson_of_t : t -> Yojson.Safe.t
val t_of_yojson : Yojson.Safe.t -> t

type domain = Signal.t

val of_domain : strategy_id:string -> price:Decimal.t -> domain -> t
(** [strategy_id] and [price] are supplied by the publishing layer
    (composition root) because [Signal.t] itself carries neither —
    [strategy_id] is composition metadata and [price] is the bar-close
    the strategy was looking at when it decided.

    [book_id] is deliberately absent: it is a Portfolio Management
    concept, not strategy's. The mapping
    [(strategy_id, instrument) → book_id] lives in PM's configuration
    and is applied by PM's inbound ACL handler when projecting this
    IE into a target update. Including [book_id] here would leak PM's
    vocabulary into strategy's outbound contract. *)
