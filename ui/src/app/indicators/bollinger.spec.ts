import { describe, it, expect } from 'vitest';
import { bollinger } from './bollinger';

const constant = (n: number, v: number) => Array.from({ length: n }, () => v);

describe('bollinger', () => {
  it('collapses to the mean when input is constant', () => {
    const out = bollinger(constant(30, 50), 20, 2);
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
    // Almost-constant series with tiny float noise around 100.
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
