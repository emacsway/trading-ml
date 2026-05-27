open Core
module Footprint_completed = Footprint_completed_integration_event

type t = { stream : Common.Footprint_bar.t Eio.Stream.t }

let make ~capacity = { stream = Eio.Stream.create capacity }
let source t = Pipe.Eio_stream.of_eio_stream t.stream

let matches_instrument
    (filter : Instrument.t)
    (vm : Strategy_external_view_models.Instrument_view_model.t) : bool =
  String.equal vm.ticker (Ticker.to_string (Instrument.ticker filter))
  && String.equal vm.venue (Mic.to_string (Instrument.venue filter))
  && Option.equal String.equal vm.isin
       (Option.map Isin.to_string (Instrument.isin filter))
  && Option.equal String.equal vm.board
       (Option.map Board.to_string (Instrument.board filter))

let footprint_bar_of ~(instrument : Instrument.t) (ev : Footprint_completed.t) :
    Common.Footprint_bar.t =
  {
    Common.Footprint_bar.instrument;
    ts = Datetime.Iso8601.parse ev.open_ts;
    high = Decimal.of_string ev.high;
    low = Decimal.of_string ev.low;
    close = Decimal.of_string ev.close;
    volume = Decimal.of_string ev.volume;
    delta = Decimal.of_string ev.delta;
    poc_price = Decimal.of_string ev.poc_price;
  }

let handle (t : t) ~(instrument : Instrument.t) (ev : Footprint_completed.t) : unit =
  if matches_instrument instrument ev.instrument then
    Eio.Stream.add t.stream (footprint_bar_of ~instrument ev)
