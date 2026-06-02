let execute ~(broker : Broker.client) (cmd : Watch_public_trades_command.t) :
    (unit, Watch_public_trades_command_handler.handle_error) Rop.t =
  match Watch_public_trades_command_handler.handle ~broker cmd with
  | Ok () -> Rop.succeed ()
  | Error errs ->
      List.iter
        (function
          | Watch_public_trades_command_handler.Validation v ->
              Log.warn "[broker watch_public_trades] %s"
                (Watch_public_trades_command_handler.validation_error_to_string v))
        errs;
      Error errs
