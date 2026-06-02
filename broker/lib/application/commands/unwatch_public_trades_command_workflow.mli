(** Command pipeline for {!Unwatch_public_trades_command.t}.

    Mirror of {!Watch_public_trades_command_workflow}: compose the handler
    with one side effect — log on validation failure. Fire-and-forget; no
    IE, no audit log, no saga correlation. *)

val execute :
  broker:Broker.client ->
  Unwatch_public_trades_command.t ->
  (unit, Unwatch_public_trades_command_handler.handle_error) Rop.t
