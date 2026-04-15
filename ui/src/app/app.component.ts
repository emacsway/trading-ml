import {
  ChangeDetectionStrategy, Component, DestroyRef, computed, effect,
  inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormsModule } from '@angular/forms';
import {
  Api, Candle, IndicatorSpec, StrategySpec, BacktestResult,
} from './api.service';
import { ChartComponent, IndicatorOverlay } from './chart.component';
import { sma, ema, bollinger } from './indicators';

interface IndicatorChoice {
  spec: IndicatorSpec;
  enabled: boolean;
  params: Record<string, number>;
  color: string;
}

const PALETTE = [
  '#f4c430', '#4fc3f7', '#ba68c8', '#ef5350', '#81c784',
  '#ff8a65', '#4db6ac', '#7986cb',
];

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [FormsModule, ChartComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="layout">
      <header>
        <h1>Finam Trading — OCaml</h1>
        <div class="controls">
          <label>Symbol
            <input [ngModel]="symbol()" (ngModelChange)="symbol.set($event)">
          </label>
          <label>Bars
            <input type="number" [ngModel]="n()"
                   (ngModelChange)="n.set(+$event)">
          </label>
          <label>Strategy
            <select [ngModel]="strategyName()"
                    (ngModelChange)="strategyName.set($event)">
              @for (s of strategies(); track s.name) {
                <option [value]="s.name">{{s.name}}</option>
              }
            </select>
          </label>
          <button (click)="runBacktest()">Run backtest</button>
        </div>
      </header>

      <section class="indicators">
        <h3>Indicators</h3>
        @for (ind of indicators(); track ind.spec.name) {
          <div class="ind-row">
            <label>
              <input type="checkbox" [ngModel]="ind.enabled"
                     (ngModelChange)="toggleIndicator(ind, $event)">
              <span [style.color]="ind.color">■</span>
              {{ind.spec.name}}
            </label>
            @for (p of ind.spec.params; track p.name) {
              <span class="param">
                {{p.name}}
                <input type="number" [ngModel]="ind.params[p.name]"
                       (ngModelChange)="updateParam(ind, p.name, +$event)"
                       style="width: 60px">
              </span>
            }
          </div>
        }
      </section>

      <app-chart [candles]="candles()" [overlays]="overlays()"></app-chart>

      @if (result(); as r) {
        <section class="result">
          <h3>Backtest — {{strategyName()}}</h3>
          <div class="grid">
            <div><b>Trades:</b> {{r.num_trades}}</div>
            <div><b>Return:</b> {{(r.total_return * 100).toFixed(2)}}%</div>
            <div><b>Max DD:</b> {{(r.max_drawdown * 100).toFixed(2)}}%</div>
            <div><b>Realized PnL:</b> {{r.realized_pnl.toFixed(2)}}</div>
          </div>
        </section>
      }
    </div>
  `,
  styles: [`
    .layout { max-width: 1400px; margin: 0 auto; padding: 16px; }
    header { display: flex; justify-content: space-between; align-items: center; }
    .controls { display: flex; gap: 12px; align-items: center; }
    .indicators { margin: 16px 0; }
    .ind-row { display: flex; gap: 12px; align-items: center; padding: 4px 0; }
    .param { opacity: 0.8; }
    .result .grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; }
  `],
})
export class AppComponent {
  private readonly api = inject(Api);
  private readonly destroyRef = inject(DestroyRef);

  readonly symbol = signal('SBER');
  readonly n = signal(500);
  readonly strategyName = signal('');
  readonly strategies = signal<StrategySpec[]>([]);
  readonly indicators = signal<IndicatorChoice[]>([]);
  readonly candles = signal<Candle[]>([]);
  readonly result = signal<BacktestResult | undefined>(undefined);

  readonly overlays = computed<IndicatorOverlay[]>(() => {
    const cs = this.candles();
    return this.indicators()
      .filter(i => i.enabled)
      .map(i => this.computeOverlay(i, cs));
  });

  constructor() {
    this.api.strategies()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe(list => {
        this.strategies.set(list);
        if (!this.strategyName() && list.length) {
          this.strategyName.set(list[0].name);
        }
      });

    this.api.indicators()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe(list => {
        this.indicators.set(list.map((spec, i) => ({
          spec,
          enabled: i < 2,
          color: PALETTE[i % PALETTE.length],
          params: Object.fromEntries(
            spec.params.map(p => [p.name, Number(p.default) || 0])),
        })));
      });

    // Candles: reload whenever symbol or n change.
    effect(() => {
      const s = this.symbol();
      const count = this.n();
      this.api.candles(s, count)
        .pipe(takeUntilDestroyed(this.destroyRef))
        .subscribe(r => this.candles.set(r.candles));
    });
  }

  toggleIndicator(ind: IndicatorChoice, enabled: boolean): void {
    this.indicators.update(list => list.map(x =>
      x === ind ? { ...x, enabled } : x));
  }

  updateParam(ind: IndicatorChoice, key: string, value: number): void {
    this.indicators.update(list => list.map(x =>
      x === ind ? { ...x, params: { ...x.params, [key]: value } } : x));
  }

  runBacktest(): void {
    this.api.backtest({
      symbol: this.symbol(),
      strategy: this.strategyName(),
      params: {},
      n: this.n(),
    })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe(r => this.result.set(r));
  }

  private computeOverlay(ind: IndicatorChoice, candles: Candle[]): IndicatorOverlay {
    const closes = candles.map(c => c.close);
    switch (ind.spec.name) {
      case 'SMA':
      case 'EMA': {
        const period = ind.params['period'] || 20;
        const series = ind.spec.name === 'EMA' ? ema(closes, period)
                                               : sma(closes, period);
        return {
          name: ind.spec.name,
          lines: [{
            label: `${ind.spec.name}(${period})`,
            color: ind.color,
            points: series.map((v, i) => ({ ts: candles[i].ts, v })),
          }],
        };
      }
      case 'BollingerBands': {
        const period = ind.params['period'] || 20;
        const k = ind.params['k'] || 2;
        const bands = bollinger(closes, period, k);
        return {
          name: 'BB',
          lines: [
            { label: 'BB upper',  color: ind.color,
              points: bands.map((x, i) => ({ ts: candles[i].ts, v: x.upper })) },
            { label: 'BB middle', color: ind.color,
              points: bands.map((x, i) => ({ ts: candles[i].ts, v: x.middle })) },
            { label: 'BB lower',  color: ind.color,
              points: bands.map((x, i) => ({ ts: candles[i].ts, v: x.lower })) },
          ],
        };
      }
      default:
        return { name: ind.spec.name, lines: [] };
    }
  }
}
