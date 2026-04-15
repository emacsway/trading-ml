import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import {
  HttpTestingController, provideHttpClientTesting,
} from '@angular/common/http/testing';
import { Api } from './api.service';

describe('Api', () => {
  let api: Api;
  let httpCtrl: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting(), Api],
    });
    api = TestBed.inject(Api);
    httpCtrl = TestBed.inject(HttpTestingController);
  });

  afterEach(() => httpCtrl.verify());

  it('GETs /api/candles with symbol and n', () => {
    api.candles('SBER', 100).subscribe();
    const req = httpCtrl.expectOne('/api/candles?symbol=SBER&n=100');
    expect(req.request.method).toBe('GET');
    req.flush({ candles: [] });
  });

  it('GETs /api/strategies', () => {
    api.strategies().subscribe(spec => expect(spec).toEqual([]));
    httpCtrl.expectOne('/api/strategies').flush([]);
  });

  it('POSTs /api/backtest with JSON body', () => {
    api.backtest({
      symbol: 'GAZP', strategy: 'SMA_Crossover',
      params: { fast: 10 }, n: 200,
    }).subscribe();
    const req = httpCtrl.expectOne('/api/backtest');
    expect(req.request.method).toBe('POST');
    expect(req.request.body).toEqual({
      symbol: 'GAZP', strategy: 'SMA_Crossover',
      params: { fast: 10 }, n: 200,
    });
    req.flush({
      num_trades: 0, total_return: 0, max_drawdown: 0,
      final_cash: 0, realized_pnl: 0, equity_curve: [], fills: [],
    });
  });
});
