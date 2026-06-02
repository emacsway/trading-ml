(** Command pipeline for {!Watch_public_trades_command.t}.

    Composes {!Watch_public_trades_command_handler.handle} with one side
    effect — log on validation failure. Watch is fire-and-forget; there is
    no IE to publish, no audit log, no saga correlation. The [Rop.t]
    return surfaces the validation error list to callers that want it. *)

val execute :
  broker:Broker.client ->
  Watch_public_trades_command.t ->
  (unit, Watch_public_trades_command_handler.handle_error) Rop.t
