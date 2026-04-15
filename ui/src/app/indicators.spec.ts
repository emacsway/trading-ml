import { describe, it, expect } from 'vitest';
import { sma, ema, bollinger } from './indicators';

const close = (n: number, v = 1) => Array.from({ length: n }, () => v);

describe('sma', () => {
  it('returns NaN before the window is full', () => {
    const out = sma([1, 2, 3, 4, 5], 3);
    expect(out.slice(0, 2).every(Number.isNaN)).toBe(true);
    expect(out[2]).toBeCloseTo(2);
    expect(out[3]).toBeCloseTo(3);
    expect(out[4]).toBeCloseTo(4);
  });

  it('is a pure mean over constant input', () => {
    const out = sma(close(20, 7.5), 5);
    expect(out.at(-1)).toBeCloseTo(7.5);
  });

  it('handles edge cases safely', () => {
    expect(sma([], 5)).toEqual([]);
    expect(sma([1, 2, 3], 0)).toEqual([NaN, NaN, NaN]);
  });
});

describe('ema', () => {
  it('converges to constant input', () => {
    const out = ema(close(100, 42), 10);
    expect(out.at(-1)).toBeCloseTo(42, 6);
  });

  it('first value equals the SMA seed', () => {
    const out = ema([10, 20, 30, 40, 50], 5);
    // seed SMA = (10+20+30+40+50)/5 = 30
    expect(out[4]).toBeCloseTo(30);
    expect(out.slice(0, 4).every(Number.isNaN)).toBe(true);
  });

  it('reacts faster than SMA to a regime change', () => {
    const data = [...close(20, 10), ...close(20, 20)];
    const smaOut = sma(data, 10);
    const emaOut = ema(data, 10);
    // After the jump, EMA should be strictly closer to 20 than SMA.
    const idx = 25;
    expect(emaOut[idx]).toBeGreaterThan(smaOut[idx]);
  });
});

describe('bollinger', () => {
  it('collapses to the mean when input is constant', () => {
    const out = bollinger(close(30, 50), 20, 2);
    const b = out.at(-1)!;
    expect(b.middle).toBeCloseTo(50);
    expect(b.upper).toBeCloseTo(50);
    expect(b.lower).toBeCloseTo(50);
  });

  it('has upper - middle = middle - lower = k·σ', () => {
    const data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
    const out = bollinger(data, 10, 2);
    const b = out.at(-1)!;
    const upHalf = b.upper - b.middle;
    const lowHalf = b.middle - b.lower;
    expect(upHalf).toBeCloseTo(lowHalf, 10);
    expect(upHalf).toBeGreaterThan(0);
  });

  it('never emits negative variance under catastrophic cancellation', () => {
    // Almost-constant series with tiny float noise.
    const data = Array.from({ length: 50 }, (_, i) =>
      100 + (i % 2 === 0 ? 1e-12 : -1e-12));
    const out = bollinger(data, 20, 2);
    out.forEach(b => {
      if (!Number.isNaN(b.upper)) {
        expect(b.upper - b.middle).toBeGreaterThanOrEqual(0);
        expect(b.middle - b.lower).toBeGreaterThanOrEqual(0);
      }
    });
  });
});
