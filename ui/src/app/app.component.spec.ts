import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { Component, provideZonelessChangeDetection, input } from '@angular/core';
import { TestBed, ComponentFixture } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import {
  HttpTestingController, provideHttpClientTesting,
} from '@angular/common/http/testing';
import { AppComponent } from './app.component';
import { ChartComponent, IndicatorOverlay } from './chart.component';
import { Candle } from './api.service';

/** Stand-in for ChartComponent — keeps the selector and public inputs, but
 *  renders nothing so lightweight-charts and its canvas needs stay out of
 *  the test environment. */
@Component({
  selector: 'app-chart',
  standalone: true,
  template: '',
})
class ChartStubComponent {
  readonly candles = input<Candle[]>([]);
  readonly overlays = input<IndicatorOverlay[]>([]);
}

describe('AppComponent', () => {
  let fixture: ComponentFixture<AppComponent>;
  let httpCtrl: HttpTestingController;

  const indicatorsCatalog = [
    { name: 'SMA', params: [{ name: 'period', type: 'int', default: 20 }] },
    { name: 'EMA', params: [{ name: 'period', type: 'int', default: 20 }] },
    { name: 'BollingerBands', params: [
      { name: 'period', type: 'int', default: 20 },
      { name: 'k', type: 'float', default: 2 },
    ]},
  ];

  const strategies = [
    { name: 'SMA_Crossover', params: [] },
    { name: 'RSI_MeanReversion', params: [] },
  ];

  const candlesFor = (n: number): Candle[] =>
    Array.from({ length: n }, (_, i) => ({
      ts: 1_700_000_000 + i * 60,
      open: 100 + i * 0.1, high: 101 + i * 0.1,
      low: 99 + i * 0.1, close: 100 + i * 0.1, volume: 1000,
    }));

  beforeEach(async () => {
    TestBed.resetTestingModule();
    TestBed.configureTestingModule({
      imports: [AppComponent],
      providers: [
        provideZonelessChangeDetection(),
        provideHttpClient(),
        provideHttpClientTesting(),
      ],
    });
    TestBed.overrideComponent(AppComponent, {
      remove: { imports: [ChartComponent] },
      add: { imports: [ChartStubComponent] },
    });

    fixture = TestBed.createComponent(AppComponent);
    httpCtrl = TestBed.inject(HttpTestingController);

    fixture.detectChanges();
    httpCtrl.expectOne('/api/strategies').flush(strategies);
    httpCtrl.expectOne('/api/indicators').flush(indicatorsCatalog);
    httpCtrl.expectOne('/api/candles?symbol=SBER&n=500').flush({
      candles: candlesFor(60),
    });
    await fixture.whenStable();
  });

  afterEach(() => httpCtrl.verify());

  it('initialises the strategy selector from the catalog', () => {
    expect(fixture.componentInstance.strategyName()).toBe('SMA_Crossover');
  });

  it('seeds indicator choices from the catalog', () => {
    const inds = fixture.componentInstance.indicators();
    expect(inds.map(i => i.spec.name)).toEqual(['SMA', 'EMA', 'BollingerBands']);
    expect(inds[0].enabled).toBe(true);
    expect(inds[1].enabled).toBe(true);
    expect(inds[2].enabled).toBe(false);
  });

  it('recomputes overlays reactively when an indicator is toggled', async () => {
    const cmp = fixture.componentInstance;
    const bb = cmp.indicators()[2];
    expect(cmp.overlays().some(o => o.name === 'BB')).toBe(false);
    cmp.toggleIndicator(bb, true);
    await fixture.whenStable();
    expect(cmp.overlays().some(o => o.name === 'BB')).toBe(true);
  });

  it('reloads candles when the symbol changes', async () => {
    fixture.componentInstance.symbol.set('GAZP');
    await fixture.whenStable();
    httpCtrl.expectOne('/api/candles?symbol=GAZP&n=500').flush({
      candles: candlesFor(30),
    });
    await fixture.whenStable();
    expect(fixture.componentInstance.candles().length).toBe(30);
  });

  it('stores the backtest result on success', async () => {
    fixture.componentInstance.runBacktest();
    const req = httpCtrl.expectOne('/api/backtest');
    req.flush({
      num_trades: 3, total_return: 0.05, max_drawdown: 0.02,
      final_cash: 1_050_000, realized_pnl: 50_000,
      equity_curve: [], fills: [],
    });
    await fixture.whenStable();
    expect(fixture.componentInstance.result()?.num_trades).toBe(3);
  });
});
