(** Command handler for {!Unwatch_public_trades_command.t}.

    Mirror of {!Watch_public_trades_command_handler}: validate the
    wire-format [symbol] into a [Core.Instrument.t], then on success call
    {!Broker.unsubscribe} with [Subscribe_public_trades]. The adapter-side
    refcount closes the upstream tape only on the 1->0 transition.
    Side-effect-only on success; failures are returned for the workflow to
    log. *)

type validation_error = Invalid_symbol of string

val validation_error_to_string : validation_error -> string

type validated_unwatch_public_trades_command = { instrument : Core.Instrument.t }

type handle_error = Validation of validation_error

val handle :
  broker:Broker.client -> Unwatch_public_trades_command.t -> (unit, handle_error) Rop.t
