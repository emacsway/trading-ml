import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';

export interface Candle {
  ts: number;
  open: number; high: number; low: number; close: number; volume: number;
}

export interface IndicatorSpec {
  name: string;
  params: { name: string; type: string; default: unknown }[];
}

export interface StrategySpec extends IndicatorSpec {}

export interface BacktestResult {
  num_trades: number;
  total_return: number;
  max_drawdown: number;
  final_cash: number;
  realized_pnl: number;
  equity_curve: { ts: number; equity: number }[];
  fills: { ts: number; side: string; quantity: number; price: number;
           fee: number; reason: string }[];
}

@Injectable({ providedIn: 'root' })
export class Api {
  private http = inject(HttpClient);

  indicators(): Observable<IndicatorSpec[]> {
    return this.http.get<IndicatorSpec[]>('/api/indicators');
  }
  strategies(): Observable<StrategySpec[]> {
    return this.http.get<StrategySpec[]>('/api/strategies');
  }
  candles(symbol: string, n: number): Observable<{ candles: Candle[] }> {
    return this.http.get<{ candles: Candle[] }>(
      `/api/candles?symbol=${symbol}&n=${n}`);
  }
  backtest(body: {
    symbol: string; strategy: string;
    params: Record<string, number | boolean>; n: number;
  }): Observable<BacktestResult> {
    return this.http.post<BacktestResult>('/api/backtest', body);
  }
}
