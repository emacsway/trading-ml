import {
  AfterViewInit, ChangeDetectionStrategy, Component, ElementRef,
  OnDestroy, effect, input, viewChild,
} from '@angular/core';
import {
  createChart, IChartApi, ISeriesApi, LineData, CandlestickData,
  CandlestickSeries, LineSeries, Time,
} from 'lightweight-charts';
import { Candle } from './api.service';
import type { IndicatorOverlay } from './indicators';
export type { IndicatorOverlay };

@Component({
  selector: 'app-chart',
  standalone: true,
  template: `<div #host class="chart-host"></div>`,
  styles: [`.chart-host { width: 100%; height: 560px; }`],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class ChartComponent implements AfterViewInit, OnDestroy {
  readonly host = viewChild.required<ElementRef<HTMLDivElement>>('host');
  readonly candles = input<Candle[]>([]);
  readonly overlays = input<IndicatorOverlay[]>([]);

  private chart?: IChartApi;
  private candleSeries?: ISeriesApi<'Candlestick'>;
  private overlaySeries: ISeriesApi<'Line'>[] = [];

  constructor() {
    // Re-render whenever inputs change.
    effect(() => {
      const cs = this.candles();
      const ov = this.overlays();
      if (this.chart && this.candleSeries) this.render(cs, ov);
    });
  }

  ngAfterViewInit(): void {
    this.chart = createChart(this.host().nativeElement, {
      layout: { background: { color: '#0f1115' }, textColor: '#d8dae0' },
      grid: {
        vertLines: { color: '#1a1d24' },
        horzLines: { color: '#1a1d24' },
      },
      timeScale: { timeVisible: true, borderColor: '#2a2e38' },
    });
    this.candleSeries = this.chart.addSeries(CandlestickSeries, {
      upColor: '#26a69a', downColor: '#ef5350',
      borderVisible: false,
      wickUpColor: '#26a69a', wickDownColor: '#ef5350',
    });
    this.render(this.candles(), this.overlays());
  }

  ngOnDestroy(): void {
    this.chart?.remove();
  }

  private render(candles: Candle[], overlays: IndicatorOverlay[]): void {
    if (!this.chart || !this.candleSeries) return;
    const bars: CandlestickData[] = candles.map(c => ({
      time: Math.floor(c.ts) as Time,
      open: c.open, high: c.high, low: c.low, close: c.close,
    }));
    this.candleSeries.setData(bars);

    for (const s of this.overlaySeries) this.chart.removeSeries(s);
    this.overlaySeries = [];
    for (const o of overlays) {
      for (const line of o.lines) {
        const s = this.chart.addSeries(LineSeries, {
          color: line.color, lineWidth: 1, priceLineVisible: false,
          title: line.label,
        });
        const pts: LineData[] = line.points
          .filter(p => p.v !== null && !Number.isNaN(p.v))
          .map(p => ({ time: Math.floor(p.ts) as Time, value: p.v }));
        s.setData(pts);
        this.overlaySeries.push(s);
      }
    }
    this.chart.timeScale().fitContent();
  }
}
