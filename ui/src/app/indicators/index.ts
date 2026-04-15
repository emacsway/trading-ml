/** Barrel — single import surface for indicators, their overlays and types.
 *  Adding a new indicator = one file for the math + (optionally) an
 *  overlay function in the same file + one line here and one line in
 *  `overlay.ts`'s registry. */

// Shared types
export type { OHLCV } from './ohlcv';
export type {
  IndicatorOverlay, OverlayLine, OverlayBar, OverlayRenderer,
} from './overlay';
export { overlayRegistry, emptyOverlay } from './overlay';

// Price-only indicators
export { sma, smaOverlay } from './sma';
export { ema, emaOverlay } from './ema';
export { wma, wmaOverlay } from './wma';
export { rsi } from './rsi';
export { bollinger, bollingerOverlay, type BBand } from './bollinger';
export { macd, type MACD } from './macd';
export { macdWeighted } from './macd_weighted';

// OHLCV indicators
export { atr } from './atr';
export { obv } from './obv';
export { ad } from './ad';
export { chaikinOscillator } from './chaikin_oscillator';
export { stochastic, type Stoch } from './stochastic';
export { mfi } from './mfi';
export { cmf } from './cmf';
export { cvi } from './cvi';
export { cvd } from './cvd';
export { volumeMa } from './volume_ma';
