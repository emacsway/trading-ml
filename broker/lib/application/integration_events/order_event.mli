(** Outbound integration events of the Broker BC.

    Single algebraic type so subscribers (SSE fan-out, audit log,
    Account-side compensation choreography) take ONE subscription
    and pattern-match on the variant they care about.

    Every variant carries [client_order_id] — the caller-supplied
    opaque handle that travels through {!Submit_order_command.t}.
    It serves three roles at once:

    - {b Wire identity} for the broker (BCS / Finam / Paper /
      Synthetic adapters use it verbatim).
    - {b Saga key} on the Account side: Account remembers
      [client_order_id ↔ reservation_id] when [Amount_reserved] is
      published, then looks the mapping up here to compensate on
      [Order_rejected] / [Order_unreachable].
    - {b SSE filter} on the UI: the browser uses it to discriminate
      events of its own [POST /api/orders] from those of other
      tabs / sessions sharing the same SSE connection.

    DTO-shaped: primitives + nested {!Queries.Order_view_model.t}.
    No domain values, no [Order.t] entity. [@@deriving yojson]
    auto-generates the on-wire JSON; the InMemory→network bus
    transition needs no other change here. *)

type t =
  | Order_accepted of {
      client_order_id : string;
      broker_order : Queries.Order_view_model.t;
    }
      (** The broker accepted the submission. [broker_order.status]
        is typically [New] / [Pending_new] but may already reflect
        an immediate partial or full fill on aggressive orders. *)
  | Order_rejected of { client_order_id : string; reason : string }
      (** The broker reached and explicitly refused the order — wire
        validation failed, account state forbade it, instrument
        not tradeable, etc. [reason] is the broker's explanation. *)
  | Order_unreachable of { client_order_id : string; reason : string }
      (** The broker could not be reached or returned a transport-
        level error (timeout, 5xx, TLS failure). Indistinguishable
        from "rejected" at the choreography level — both compensate
        the reservation — but kept separate so SSE / audit can
        surface the cause distinctly. *)
[@@deriving yojson]

val client_order_id_of : t -> string
(** Extract [client_order_id] regardless of variant. Convenience
    accessor for filter-by-cid subscribers and compensation lookup. *)
