include Target_portfolio_updated_integration_event_t
include Target_portfolio_updated_integration_event_j

let yojson_of_t (v : t) : Yojson.Safe.t = Yojson.Safe.from_string (string_of_t v)
let t_of_yojson (j : Yojson.Safe.t) : t = t_of_string (Yojson.Safe.to_string j)

type domain = Portfolio_management.Target_portfolio.Events.Target_set.t

let of_change (c : Portfolio_management.Target_portfolio.Events.Target_set.change) :
    change =
  {
    instrument = Instrument_view_model.of_domain c.instrument;
    previous_qty = Decimal.to_string c.previous_qty;
    new_qty = Decimal.to_string c.new_qty;
  }

let of_domain (ev : domain) : t =
  {
    book_id = Portfolio_management.Common.Book_id.to_string ev.book_id;
    source = ev.source;
    proposed_at = Datetime.Iso8601.format ev.proposed_at;
    changed = List.map of_change ev.changed;
  }
