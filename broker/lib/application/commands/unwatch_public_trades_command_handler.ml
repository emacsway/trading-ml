open Core

type validation_error = Invalid_symbol of string

let validation_error_to_string = function
  | Invalid_symbol s -> Printf.sprintf "invalid symbol: %S" s

type validated_unwatch_public_trades_command = { instrument : Instrument.t }

type handle_error = Validation of validation_error

let parse_instrument raw : (Instrument.t, validation_error) Rop.t =
  try Rop.succeed (Instrument.of_qualified raw)
  with Invalid_argument _ | Failure _ -> Rop.fail (Invalid_symbol raw)

let validate (cmd : Unwatch_public_trades_command.t) :
    (validated_unwatch_public_trades_command, validation_error) Rop.t =
  let open Rop in
  let+ instrument = parse_instrument cmd.symbol in
  { instrument }

let unwatch ~(broker : Broker.client) (v : validated_unwatch_public_trades_command) : unit
    =
  Broker.unsubscribe broker (Subscribe_public_trades { instrument = v.instrument })

let handle ~(broker : Broker.client) (cmd : Unwatch_public_trades_command.t) :
    (unit, handle_error) Rop.t =
  match validate cmd with
  | Error errs -> Error (List.map (fun e -> Validation e) errs)
  | Ok v ->
      unwatch ~broker v;
      Rop.succeed ()
