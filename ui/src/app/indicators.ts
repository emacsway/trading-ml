/** Pure, DOM-free indicator math used by the UI for snappy overlay
 *  recomputation. Mirrors the OCaml incremental implementations in
 *  `lib/indicators/` — any divergence is a bug and must be caught by a
 *  test that compares the two. */

export function sma(data: number[], period: number): number[] {
  const out = new Array<number>(data.length).fill(NaN);
  if (!data.length || period <= 0) return out;
  let sum = 0;
  for (let i = 0; i < data.length; i++) {
    sum += data[i];
    if (i >= period) sum -= data[i - period];
    if (i >= period - 1) out[i] = sum / period;
  }
  return out;
}

export function ema(data: number[], period: number): number[] {
  const out = new Array<number>(data.length).fill(NaN);
  if (!data.length || period <= 0) return out;
  const a = 2 / (period + 1);
  let seed = 0;
  let value: number | null = null;
  for (let i = 0; i < data.length; i++) {
    if (i < period - 1) { seed += data[i]; continue; }
    if (i === period - 1) { seed += data[i]; value = seed / period; }
    else value = a * data[i] + (1 - a) * (value as number);
    out[i] = value;
  }
  return out;
}

export interface BBand { lower: number; middle: number; upper: number; }

export function bollinger(data: number[], period: number, k: number): BBand[] {
  const out: BBand[] = data.map(() => ({ lower: NaN, middle: NaN, upper: NaN }));
  if (period <= 1 || k <= 0) return out;
  let sum = 0, sumSq = 0;
  for (let i = 0; i < data.length; i++) {
    sum += data[i];
    sumSq += data[i] * data[i];
    if (i >= period) {
      sum -= data[i - period];
      sumSq -= data[i - period] * data[i - period];
    }
    if (i >= period - 1) {
      const mean = sum / period;
      // Guard against catastrophic cancellation near constant inputs.
      const variance = Math.max(0, sumSq / period - mean * mean);
      const sd = Math.sqrt(variance);
      out[i] = { middle: mean, upper: mean + k * sd, lower: mean - k * sd };
    }
  }
  return out;
}
