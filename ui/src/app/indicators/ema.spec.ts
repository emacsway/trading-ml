import { describe, it, expect } from 'vitest';
import { ema } from './ema';
import { sma } from './sma';

const constant = (n: number, v: number) => Array.from({ length: n }, () => v);

describe('ema', () => {
  it('converges to constant input', () => {
    const out = ema(constant(100, 42), 10);
    expect(out.at(-1)).toBeCloseTo(42, 6);
  });

  it('first emitted value equals the SMA seed', () => {
    const out = ema([10, 20, 30, 40, 50], 5);
    // seed SMA = (10+20+30+40+50)/5 = 30
    expect(out[4]).toBeCloseTo(30);
    expect(out.slice(0, 4).every(Number.isNaN)).toBe(true);
  });

  it('reacts faster than SMA to a regime change', () => {
    const data = [...constant(20, 10), ...constant(20, 20)];
    const smaOut = sma(data, 10);
    const emaOut = ema(data, 10);
    // A few bars after the jump, EMA should be strictly closer to 20.
    const idx = 25;
    expect(emaOut[idx]).toBeGreaterThan(smaOut[idx]);
  });
});
