/** Overlay infrastructure: types and registry.
 *  Each indicator that renders onto the price chart exports its own
 *  `<name>Overlay` function from its own file; this module only wires the
 *  name-to-renderer table so adding a new visual indicator remains a
 *  one-file change (implementation + renderer in its own file, then
 *  one line in the registry below). */

import type { OHLCV } from './ohlcv';
import { smaOverlay } from './sma';
import { emaOverlay } from './ema';
import { wmaOverlay } from './wma';
import { bollingerOverlay } from './bollinger';

export interface OverlayBar extends OHLCV {
  ts: number;
}

export interface OverlayLine {
  label: string;
  color: string;
  points: { ts: number; v: number }[];
}

export interface IndicatorOverlay {
  name: string;
  lines: OverlayLine[];
}

export type OverlayRenderer = (
  bars: OverlayBar[],
  params: Record<string, number>,
  color: string,
) => IndicatorOverlay;

/** Map from indicator name (as reported by the OCaml catalog) to renderer.
 *  Indicators absent from this map are valid but not drawn. */
export const overlayRegistry: Record<string, OverlayRenderer> = {
  'SMA': smaOverlay,
  'EMA': emaOverlay,
  'WMA': wmaOverlay,
  'BollingerBands': bollingerOverlay,
};

export function emptyOverlay(name: string): IndicatorOverlay {
  return { name, lines: [] };
}
