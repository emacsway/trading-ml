import { describe, it, expect } from 'vitest';
import { cvdTrue, parseDelta, parseOpenTs, type FootprintBar } from './footprint';

const bar = (ts: number, delta: number): FootprintBar => ({ ts, delta });

describe('cvdTrue', () => {
  it('is the running sum of measured per-bar deltas', () => {
    const bars = [bar(1, 5), bar(2, -3), bar(3, 2)];
    // unlike the candle proxy, the delta is taken verbatim, not estimated
    expect(cvdTrue(bars)).toEqual([5, 2, 4]);
  });

  it('anchors at 0 before the first bar', () => {
    expect(cvdTrue([bar(1, 7)])).toEqual([7]);
  });

  it('handles an empty window', () => {
    expect(cvdTrue([])).toEqual([]);
  });

  it('preserves negative cumulative excursions', () => {
    expect(cvdTrue([bar(1, -2), bar(2, -3)])).toEqual([-2, -5]);
  });
});

describe('parseDelta', () => {
  it('parses a signed decimal-string delta into a number', () => {
    expect(parseDelta('-2')).toBe(-2);
    expect(parseDelta('15.5')).toBe(15.5);
  });
});

describe('parseOpenTs', () => {
  it('converts ISO-8601 to unix epoch seconds', () => {
    expect(parseOpenTs('1970-01-01T00:00:00Z')).toBe(0);
    expect(parseOpenTs('2024-01-15T10:00:00Z')).toBe(Date.UTC(2024, 0, 15, 10) / 1000);
  });
});
