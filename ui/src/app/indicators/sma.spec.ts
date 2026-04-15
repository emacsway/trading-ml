import { describe, it, expect } from 'vitest';
import { sma } from './sma';

const constant = (n: number, v: number) => Array.from({ length: n }, () => v);

describe('sma', () => {
  it('returns NaN before the window is full', () => {
    const out = sma([1, 2, 3, 4, 5], 3);
    expect(out.slice(0, 2).every(Number.isNaN)).toBe(true);
    expect(out[2]).toBeCloseTo(2);
    expect(out[3]).toBeCloseTo(3);
    expect(out[4]).toBeCloseTo(4);
  });

  it('is a pure mean over constant input', () => {
    const out = sma(constant(20, 7.5), 5);
    expect(out.at(-1)).toBeCloseTo(7.5);
  });

  it('handles edge cases safely', () => {
    expect(sma([], 5)).toEqual([]);
    expect(sma([1, 2, 3], 0)).toEqual([NaN, NaN, NaN]);
  });
});
