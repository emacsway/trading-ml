/** Footprint domain types for the UI and the *true* Cumulative Volume
 *  Delta derived from them.
 *
 *  Unlike the candle-range CVD proxy (indicators/cvd.ts), which estimates
 *  per-bar delta from the close's position within the range, this CVD is
 *  the running sum of the REAL aggressor-signed delta the order_flow BC
 *  measures from the public tape (ADR 0032). The per-bar figure is a
 *  fact carried on the wire; the *cumulative* sum is a presentation
 *  projection computed here in the consumer, anchored at the start of the
 *  loaded window. */

import { Decimal } from '../decimal';
import {
  applyStyle,
  type IndicatorOverlay, type OverlayStyle,
} from '../indicators/overlay';

/** One sealed footprint bar as the chart consumes it: the bar's open
 *  time and its signed delta, both projected from the wire DTO. Prices
 *  and per-price clusters exist on the wire but the CVD line needs only
 *  (ts, delta); the cluster grid (a later phase) reads the full DTO. */
export interface FootprintBar {
  ts: number;
  delta: number;
}

/** Cumulative Volume Delta from measured per-bar deltas: the running sum,
 *  anchored at 0 before the first bar of the window. Order-preserving;
 *  the caller passes bars oldest-first (as /api/footprints returns them). */
export function cvdTrue(bars: FootprintBar[]): number[] {
  const out = new Array<number>(bars.length);
  let sum = 0;
  for (let i = 0; i < bars.length; i++) {
    sum += bars[i].delta;
    out[i] = sum;
  }
  return out;
}

/** Overlay for the true CVD line, drawn in its own secondary pane
 *  ('cvd-true', distinct from the proxy's 'cvd' pane so both can coexist
 *  during the transition). */
export function cvdTrueOverlay(
  bars: FootprintBar[],
  style: OverlayStyle,
): IndicatorOverlay {
  const series = cvdTrue(bars);
  return {
    name: 'CVD (order flow)',
    pane: 'cvd-true',
    lines: [
      {
        label: 'CVD',
        color: style.color,
        ...applyStyle(style),
        points: series.map((v, i) => ({ ts: bars[i].ts, v })),
      },
    ],
  };
}

/** ISO-8601 [open_ts] (the wire form) → unix epoch seconds, matching the
 *  [ts: number] the chart's time scale uses for candles. */
export function parseOpenTs(iso: string): number {
  return Math.floor(Date.parse(iso) / 1000);
}

/** Project a wire footprint DTO's signed [delta] (a decimal string,
 *  ADR 0007) into the chart's [number] domain — the same explicit lossy
 *  step the candle parser makes via Decimal.toNumber(). */
export function parseDelta(delta: string): number {
  return Decimal.fromString(delta).toNumber();
}
