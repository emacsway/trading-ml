type t = {
  correlation_id : string;
  side : string;
  instrument : Queries.Instrument_view_model.t;
  quantity : string;
  reason : string;
}
[@@deriving yojson]
