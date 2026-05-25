(** Outbound [TradesGetAndSubscribeV2] envelope — the account-wide
    fill feed for a [(exchange, portfolio)]. Correlated by [guid]; JWT
    in the [token] field. [skipHistory] drops the session backlog so
    only live fills arrive (the REST [/trades] poll covers catch-up via
    the transport supervisor). *)

let subscribe ~(cfg : Config.t) ~token ~guid () : Yojson.Safe.t =
  `Assoc
    [
      ("opcode", `String "TradesGetAndSubscribeV2");
      ("exchange", `String cfg.Config.default_exchange);
      ("portfolio", `String cfg.Config.portfolio);
      ("skipHistory", `Bool true);
      ("format", `String "Simple");
      ("token", `String token);
      ("guid", `String guid);
    ]
