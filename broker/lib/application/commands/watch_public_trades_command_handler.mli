(** Command handler for {!Watch_public_trades_command.t}.

    Two phases in one Rop pipeline:

    - {b Validate}: parse the wire-format [symbol] back into a
      [Core.Instrument.t].
    - {b Watch}: on validation success, call {!Broker.subscribe} with
      [Subscribe_public_trades] on the injected port. The adapter-side
      refcount merges this caller with any other watcher (including the
      operator watchlist) on the same instrument; the upstream venue tape
      opens only on the 0->1 transition.

    Side-effect-only on success: no IE published, no audit entry. Failures
    are returned to the enclosing
    {!Watch_public_trades_command_workflow.execute} so it can log them. *)

type validation_error = Invalid_symbol of string

val validation_error_to_string : validation_error -> string

type validated_watch_public_trades_command = { instrument : Core.Instrument.t }

type handle_error = Validation of validation_error

val handle :
  broker:Broker.client -> Watch_public_trades_command.t -> (unit, handle_error) Rop.t
