(** Iceberg — Show-and-Refill — strategy.

    At any moment one placement of size [visible_qty] (or the
    remainder, whichever is smaller) sits at the venue. When that
    chunk is fully filled, Iceberg emits the next chunk. Repeats
    until [Σ chunks = total_quantity] and the last chunk is
    fully filled.

    Strict-serial: never more than one placement outstanding.
    Partial fills accumulate on the current chunk; the next chunk
    is emitted only after the current chunk's cumulative fill
    reaches its target. Tick / Volume_bar / Price_quote ignored.

    Rejection / unreachable / cancelled on the current chunk
    terminates the strategy as Failed — Iceberg does not retry
    a chunk against the same venue. *)

(*@ function dec_raw (d : Decimal.t) : integer *)

type state

val init :
  intent:Values.Trade_intent.t ->
  params:Values.Iceberg_params.t ->
  now:int64 ->
  state * Decision.t
(*@ s, d = init ~intent ~params ~now
    requires dec_raw intent.Values.Trade_intent.total_quantity > 0
    requires dec_raw params.Values.Iceberg_params.visible_qty > 0
    ensures List.length d.Decision.submit = 1
    ensures d.Decision.terminal = Decision.Continue *)

val on_event : state -> Input.t -> now:int64 -> state * Decision.t

val is_complete : state -> bool
