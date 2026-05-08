(** BDD specification for the Place_order saga.

    Drives the saga end-to-end through the engine + recording
    dispatch, exercising the happy path and three compensation
    paths. Idempotency and late-event silencing are pinned in
    separate scenarios. *)

module Gherkin = Gherkin_edsl
module Pm = Execution_management_process_managers.Place_order_pm
open Test_harness

let cid = "saga-component-A"

let is_reserve = function
  | Pm.Dispatch_reserve _ -> true
  | _ -> false
let is_submit = function
  | Pm.Dispatch_submit _ -> true
  | _ -> false
let is_release = function
  | Pm.Dispatch_release _ -> true
  | _ -> false

let count p l = List.length (List.filter p l)

let happy_path =
  Gherkin.scenario
    "An approved trade flows through reserve → submit → accepted into a Done saga"
    fresh_ctx
    [
      Gherkin.given "a fresh saga engine" (fun ctx -> ctx);
      Gherkin.when_ "the saga starts for an approved trade" (fun ctx ->
          ctx
          |> start_saga ~correlation_id:cid ~book_id:"alpha" ~symbol:"SBER@MISX"
               ~side:"BUY" ~quantity:"10" ~price:"100");
      Gherkin.then_ "a Reserve command is dispatched immediately" (fun ctx ->
          let cmds = dispatched_commands ctx in
          Alcotest.(check int) "one Reserve" 1 (count is_reserve cmds);
          Alcotest.(check int) "no Submit yet" 0 (count is_submit cmds);
          Alcotest.(check int) "no Release" 0 (count is_release cmds));
      Gherkin.when_ "the account announces the reservation succeeded" (fun ctx ->
          ctx
          |> push_amount_reserved ~correlation_id:cid ~reservation_id:42
               ~symbol:"SBER@MISX" ~side:"BUY" ~quantity:"10" ~price:"100"
               ~reserved_cash:"1000");
      Gherkin.then_ "the saga dispatches a Submit_order command" (fun ctx ->
          let cmds = dispatched_commands ctx in
          Alcotest.(check int) "one Submit" 1 (count is_submit cmds));
      Gherkin.when_ "the broker accepts the order" (fun ctx ->
          ctx
          |> push_order_accepted ~correlation_id:cid ~reservation_id:42
               ~symbol:"SBER@MISX" ~side:"BUY" ~quantity:"10");
      Gherkin.then_ "the saga reaches Done and is dropped from the engine" (fun ctx ->
          (match saga_state ctx ~correlation_id:cid with
          | None -> ()
          | Some _ -> Alcotest.fail "expected the terminal saga to be dropped");
          Alcotest.(check int) "no active sagas" 0 (active_count ctx));
      Gherkin.then_ "no Release was dispatched on the happy path" (fun ctx ->
          Alcotest.(check int)
            "release count" 0
            (count is_release (dispatched_commands ctx)));
    ]

let reservation_rejected_compensates_without_release =
  Gherkin.scenario
    "When the account refuses the reservation the saga compensates without releasing"
    fresh_ctx
    [
      Gherkin.given "a fresh saga engine and a started saga" (fun ctx ->
          ctx
          |> start_saga ~correlation_id:cid ~book_id:"alpha" ~symbol:"SBER@MISX"
               ~side:"BUY" ~quantity:"10" ~price:"100");
      Gherkin.when_ "the account announces a reservation rejection" (fun ctx ->
          ctx
          |> push_reservation_rejected ~correlation_id:cid ~symbol:"SBER@MISX" ~side:"BUY"
               ~quantity:"10" ~reason:"insufficient cash");
      Gherkin.then_ "the saga reaches Compensated and is dropped" (fun ctx ->
          Alcotest.(check int) "no active sagas" 0 (active_count ctx));
      Gherkin.then_ "no Release is dispatched — there is no reservation to release"
        (fun ctx ->
          Alcotest.(check int)
            "release count" 0
            (count is_release (dispatched_commands ctx)));
      Gherkin.then_ "no Submit_order is dispatched either" (fun ctx ->
          Alcotest.(check int)
            "submit count" 0
            (count is_submit (dispatched_commands ctx)));
    ]

let order_rejected_releases_then_compensates =
  Gherkin.scenario "A broker-rejected order triggers Release and the saga compensates"
    fresh_ctx
    [
      Gherkin.given "a saga that has already submitted to the broker" (fun ctx ->
          ctx
          |> start_saga ~correlation_id:cid ~book_id:"alpha" ~symbol:"SBER@MISX"
               ~side:"BUY" ~quantity:"10" ~price:"100"
          |> push_amount_reserved ~correlation_id:cid ~reservation_id:42
               ~symbol:"SBER@MISX" ~side:"BUY" ~quantity:"10" ~price:"100"
               ~reserved_cash:"1000");
      Gherkin.when_ "the broker rejects the order" (fun ctx ->
          ctx
          |> push_order_rejected ~correlation_id:cid ~reservation_id:42
               ~reason:"no liquidity");
      Gherkin.then_ "a Release for that reservation is dispatched" (fun ctx ->
          let releases =
            List.filter_map
              (function
                | Pm.Dispatch_release { reservation_id; correlation_id }
                  when correlation_id = cid -> Some reservation_id
                | _ -> None)
              (dispatched_commands ctx)
          in
          Alcotest.(check (list int)) "release for reservation 42" [ 42 ] releases);
      Gherkin.then_ "the saga reaches Compensated and is dropped" (fun ctx ->
          Alcotest.(check int) "no active sagas" 0 (active_count ctx));
    ]

let order_unreachable_releases_then_compensates =
  Gherkin.scenario "An unreachable broker triggers Release and the saga compensates"
    fresh_ctx
    [
      Gherkin.given "a saga that has already submitted to the broker" (fun ctx ->
          ctx
          |> start_saga ~correlation_id:cid ~book_id:"alpha" ~symbol:"SBER@MISX"
               ~side:"BUY" ~quantity:"10" ~price:"100"
          |> push_amount_reserved ~correlation_id:cid ~reservation_id:42
               ~symbol:"SBER@MISX" ~side:"BUY" ~quantity:"10" ~price:"100"
               ~reserved_cash:"1000");
      Gherkin.when_ "the broker is unreachable" (fun ctx ->
          ctx
          |> push_order_unreachable ~correlation_id:cid ~reservation_id:42
               ~reason:"timeout");
      Gherkin.then_ "a Release for that reservation is dispatched" (fun ctx ->
          Alcotest.(check int)
            "release count" 1
            (count is_release (dispatched_commands ctx)));
      Gherkin.then_ "the saga reaches Compensated and is dropped" (fun ctx ->
          Alcotest.(check int) "no active sagas" 0 (active_count ctx));
    ]

let duplicate_amount_reserved_is_absorbed =
  Gherkin.scenario "A duplicate reservation announcement does not double-submit" fresh_ctx
    [
      Gherkin.given "a saga that has already submitted to the broker" (fun ctx ->
          ctx
          |> start_saga ~correlation_id:cid ~book_id:"alpha" ~symbol:"SBER@MISX"
               ~side:"BUY" ~quantity:"10" ~price:"100"
          |> push_amount_reserved ~correlation_id:cid ~reservation_id:42
               ~symbol:"SBER@MISX" ~side:"BUY" ~quantity:"10" ~price:"100"
               ~reserved_cash:"1000");
      Gherkin.when_ "the same reservation announcement arrives a second time" (fun ctx ->
          ctx
          |> push_amount_reserved ~correlation_id:cid ~reservation_id:42
               ~symbol:"SBER@MISX" ~side:"BUY" ~quantity:"10" ~price:"100"
               ~reserved_cash:"1000");
      Gherkin.then_ "the saga still has exactly one Submit_order in its dispatch log"
        (fun ctx ->
          Alcotest.(check int)
            "submit count" 1
            (count is_submit (dispatched_commands ctx)));
      Gherkin.then_ "the saga remains in its already-submitted state" (fun ctx ->
          match saga_state ctx ~correlation_id:cid with
          | Some (Pm.Submitted _) -> ()
          | _ -> Alcotest.fail "expected Submitted");
    ]

let event_for_terminated_saga_is_silently_dropped =
  Gherkin.scenario "An event arriving after the saga has reached Done is silently dropped"
    fresh_ctx
    [
      Gherkin.given "a saga that already reached Done" (fun ctx ->
          ctx
          |> start_saga ~correlation_id:cid ~book_id:"alpha" ~symbol:"SBER@MISX"
               ~side:"BUY" ~quantity:"10" ~price:"100"
          |> push_amount_reserved ~correlation_id:cid ~reservation_id:42
               ~symbol:"SBER@MISX" ~side:"BUY" ~quantity:"10" ~price:"100"
               ~reserved_cash:"1000"
          |> push_order_accepted ~correlation_id:cid ~reservation_id:42
               ~symbol:"SBER@MISX" ~side:"BUY" ~quantity:"10");
      Gherkin.when_ "a late Order_rejected with the same correlation_id arrives"
        (fun ctx ->
          ctx
          |> push_order_rejected ~correlation_id:cid ~reservation_id:42
               ~reason:"late echo");
      Gherkin.then_ "no extra dispatch is produced" (fun ctx ->
          Alcotest.(check int)
            "release count" 0
            (count is_release (dispatched_commands ctx)));
      Gherkin.then_ "no saga instance is resurrected" (fun ctx ->
          Alcotest.(check int) "active count" 0 (active_count ctx));
    ]

let unrelated_correlation_id_does_not_advance_other_sagas =
  Gherkin.scenario
    "An event for an unknown correlation_id does not affect any running saga" fresh_ctx
    [
      Gherkin.given "a saga running for cid \"saga-A\"" (fun ctx ->
          ctx
          |> start_saga ~correlation_id:"saga-A" ~book_id:"alpha" ~symbol:"SBER@MISX"
               ~side:"BUY" ~quantity:"10" ~price:"100");
      Gherkin.when_ "an Amount_reserved arrives for a different cid \"saga-B\""
        (fun ctx ->
          ctx
          |> push_amount_reserved ~correlation_id:"saga-B" ~reservation_id:42
               ~symbol:"SBER@MISX" ~side:"BUY" ~quantity:"10" ~price:"100"
               ~reserved_cash:"1000");
      Gherkin.then_ "saga-A is still in Awaiting_reservation" (fun ctx ->
          match saga_state ctx ~correlation_id:"saga-A" with
          | Some (Pm.Awaiting_reservation _) -> ()
          | _ -> Alcotest.fail "expected saga-A in Awaiting_reservation");
      Gherkin.then_ "no Submit_order has been dispatched for saga-A" (fun ctx ->
          Alcotest.(check int)
            "submit count" 0
            (count is_submit (dispatched_commands ctx)));
    ]

let feature =
  Gherkin.feature "Place_order saga"
    [
      happy_path;
      reservation_rejected_compensates_without_release;
      order_rejected_releases_then_compensates;
      order_unreachable_releases_then_compensates;
      duplicate_amount_reserved_is_absorbed;
      event_for_terminated_saga_is_silently_dropped;
      unrelated_correlation_id_does_not_advance_other_sagas;
    ]
