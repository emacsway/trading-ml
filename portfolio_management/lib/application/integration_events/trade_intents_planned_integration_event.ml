include Trade_intents_planned_integration_event_t
include Trade_intents_planned_integration_event_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

type domain = Portfolio_management.Reconciliation.Events.Trades_planned.t

let of_domain (ev : domain) : t =
  {
    book_id = Portfolio_management.Common.Book_id.to_string ev.book_id;
    trades =
      List.map
        (fun i ->
          {
            correlation_id = Correlation_id.to_string (Correlation_id.generate ());
            intent = Trade_intent_view_model.of_domain i;
          })
        ev.trades;
    computed_at = Datetime.Iso8601.format ev.computed_at;
  }
