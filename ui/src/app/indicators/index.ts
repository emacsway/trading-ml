/** Barrel — one place to register every indicator so the UI can import
 *  `{ sma, ema, bollinger, … }` without caring about file layout.
 *  Adding a new indicator = one file + one line here. */

export { sma } from './sma';
export { ema } from './ema';
export { bollinger, type BBand } from './bollinger';
