(** Outbound [unsubscribe] envelope — channel-agnostic: it cancels a
    single subscription by its [guid], whatever opcode opened it. *)

let make ~token ~guid : Yojson.Safe.t =
  `Assoc
    [
      ("opcode", `String "unsubscribe"); ("token", `String token); ("guid", `String guid);
    ]
