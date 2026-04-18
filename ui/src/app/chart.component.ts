import {
  AfterViewInit, ChangeDetectionStrategy, Component, ElementRef,
  OnDestroy, effect, input, signal, viewChild,
} from '@angular/core';
import {
  createChart, IChartApi, IPriceLine, ISeriesApi,
  LineData, CandlestickData, HistogramData,
  CandlestickSeries, LineSeries, HistogramSeries,
  LineStyle as LwLineStyle, Time,
} from 'lightweight-charts';
import { Candle } from './api.service';
import {
  withOpacity, PRICE_PANE,
  type IndicatorOverlay, type LineStyle,
} from './indicators';
export type { IndicatorOverlay };

/** Map our string identifiers to lightweight-charts' numeric enum. */
const LINE_STYLE: Record<LineStyle, LwLineStyle> = {
  'solid':         LwLineStyle.Solid,
  'dotted':        LwLineStyle.Dotted,
  'dashed':        LwLineStyle.Dashed,
  'large-dashed':  LwLineStyle.LargeDashed,
  'sparse-dotted': LwLineStyle.SparseDotted,
};

@Component({
  selector: 'app-chart',
  standalone: true,
  template: `
    <div class="chart-wrap">
      <div #host class="chart-host"></div>
      <div class="measure-hud">{{ measureLabel() || 'Shift+click — measure' }}</div>
    </div>
  `,
  styles: [`
    .chart-wrap { position: relative; }
    .chart-host { width: 100%; height: 720px; }
    .measure-hud {
      position: absolute; top: 8px; left: 12px; z-index: 10;
      background: rgba(18,20,26,0.9); color: #ffcc00;
      padding: 4px 8px; border: 1px solid #3a3f4a; border-radius: 4px;
      font: 12px/1.4 ui-monospace, monospace;
      pointer-events: none; user-select: none;
    }
  `],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class ChartComponent implements AfterViewInit, OnDestroy {
  readonly host = viewChild.required<ElementRef<HTMLDivElement>>('host');
  readonly candles = input<Candle[]>([]);
  readonly overlays = input<IndicatorOverlay[]>([]);
  /** Opaque key identifying the current data series (e.g.
   *  [symbol/timeframe/n]). When it changes the chart auto-fits;
   *  otherwise the user's pan/zoom is preserved across live
   *  appends and trailing-window trims. */
  readonly seriesKey = input<string>('');

  private chart?: IChartApi;
  private candleSeries?: ISeriesApi<'Candlestick'>;
  private overlaySeries: ISeriesApi<'Line' | 'Histogram'>[] = [];
  private lastFittedKey?: string;

  /** Price measurement tool. Anchor is set on first Shift+click;
   *  subsequent Shift+clicks move the second point and update the
   *  delta. Escape (or a new [seriesKey]) clears the measurement. */
  private shiftDown = false;
  private anchor?: { price: number };
  private anchorLine?: IPriceLine;
  private endpointLine?: IPriceLine;
  readonly measureLabel = signal<string>('');
  private onKeyDown = (e: KeyboardEvent) => {
    if (e.key === 'Shift') this.shiftDown = true;
    if (e.key === 'Escape') this.clearMeasure();
  };
  private onKeyUp = (e: KeyboardEvent) => {
    if (e.key === 'Shift') this.shiftDown = false;
  };

  constructor() {
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
      /* lightweight-charts renders [Time] in UTC by default. We keep the
         wire format as epoch seconds (UTC) but format the axis labels and
         crosshair tooltip in the browser's local timezone. */
      localization: {
        timeFormatter: (t: Time) =>
          new Date((t as number) * 1000).toLocaleString(),
      },
      timeScale: {
        timeVisible: true,
        borderColor: '#2a2e38',
        tickMarkFormatter: (t: Time) => {
          const d = new Date((t as number) * 1000);
          return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        },
      },
    });
    this.candleSeries = this.chart.addSeries(CandlestickSeries, {
      upColor: '#26a69a', downColor: '#ef5350',
      borderVisible: false,
      wickUpColor: '#26a69a', wickDownColor: '#ef5350',
    });
    this.chart.subscribeClick((param) => this.handleMeasureClick(param));
    window.addEventListener('keydown', this.onKeyDown);
    window.addEventListener('keyup', this.onKeyUp);
    this.render(this.candles(), this.overlays());
  }

  ngOnDestroy(): void {
    window.removeEventListener('keydown', this.onKeyDown);
    window.removeEventListener('keyup', this.onKeyUp);
    this.chart?.remove();
  }

  /** Two-click price-delta tool. Shift+click #1 sets the anchor;
   *  each subsequent Shift+click moves the endpoint. The HUD and
   *  the endpoint price-line show [Δ abs (Δ rel %)]. A non-shift
   *  click or a new [seriesKey] clears the state. */
  private handleMeasureClick(param: {
    point?: { x: number; y: number };
  }): void {
    if (!this.candleSeries || !param.point) return;
    if (!this.shiftDown) return;
    const price = this.candleSeries.coordinateToPrice(param.point.y);
    if (price === null) return;
    if (!this.anchor) {
      this.anchor = { price };
      this.anchorLine = this.candleSeries.createPriceLine({
        price, color: '#ffcc00', lineWidth: 1,
        lineStyle: LwLineStyle.Dashed, axisLabelVisible: true, title: 'A',
      });
      this.measureLabel.set(`A = ${this.fmt(price)}`);
    } else {
      const abs = price - this.anchor.price;
      const rel = this.anchor.price !== 0
        ? abs / this.anchor.price * 100 : 0;
      const sign = abs >= 0 ? '+' : '';
      const label = `Δ ${sign}${this.fmt(abs)} (${sign}${rel.toFixed(2)}%)`;
      if (this.endpointLine) this.candleSeries.removePriceLine(this.endpointLine);
      this.endpointLine = this.candleSeries.createPriceLine({
        price, color: '#ffcc00', lineWidth: 1,
        lineStyle: LwLineStyle.Dashed, axisLabelVisible: true, title: 'B',
      });
      this.measureLabel.set(
        `A = ${this.fmt(this.anchor.price)}   B = ${this.fmt(price)}   ${label}`);
    }
  }

  private clearMeasure(): void {
    if (!this.candleSeries) return;
    if (this.anchorLine) this.candleSeries.removePriceLine(this.anchorLine);
    if (this.endpointLine) this.candleSeries.removePriceLine(this.endpointLine);
    this.anchor = undefined;
    this.anchorLine = undefined;
    this.endpointLine = undefined;
    this.measureLabel.set('');
  }

  /** Four significant decimals is enough for equities in roubles
   *  (kopeck precision) and loose enough for typical FX/crypto
   *  pairs shown on this UI. */
  private fmt(x: number): string {
    const abs = Math.abs(x);
    if (abs >= 100) return x.toFixed(2);
    if (abs >= 1)   return x.toFixed(4);
    return x.toFixed(6);
  }

  /** Recreates all overlay series and the secondary panes they require.
   *  Secondary panes are keyed by [overlay.pane]; two overlays sharing a
   *  key are stacked in the same pane, which is what MACD/Signal/Hist and
   *  Stochastic %K/%D rely on. */
  private render(candles: Candle[], overlays: IndicatorOverlay[]): void {
    if (!this.chart || !this.candleSeries) return;

    const bars: CandlestickData[] = candles.map(c => ({
      time: Math.floor(c.ts) as Time,
      open: c.open, high: c.high, low: c.low, close: c.close,
    }));
    this.candleSeries.setData(bars);

    // Tear down previous overlay series. Removing the last series from a
    // pane auto-collapses that pane in lightweight-charts v5.
    for (const s of this.overlaySeries) this.chart.removeSeries(s);
    this.overlaySeries = [];

    // Assign pane indices: 'price' → 0, every other pane key in first-seen order.
    const paneIndex = new Map<string, number>([[PRICE_PANE, 0]]);
    for (const o of overlays) {
      if (!paneIndex.has(o.pane)) paneIndex.set(o.pane, paneIndex.size);
    }
    // Ensure enough panes exist.
    while (this.chart.panes().length < paneIndex.size) this.chart.addPane();

    for (const o of overlays) {
      const idx = paneIndex.get(o.pane)!;
      for (const line of o.lines) {
        if (line.kind === 'histogram') {
          // Histograms honour per-point colour (for red/green volume bars);
          // line-level opacity is folded into those when points don't set
          // their own colour.
          const baseColor = withOpacity(line.color, line.opacity);
          const s = this.chart.addSeries(HistogramSeries, {
            color: baseColor,
            priceLineVisible: false,
            title: line.label,
            priceFormat: { type: 'volume' },
          }, idx);
          const pts: HistogramData[] = line.points
            .filter(p => p.v !== null && !Number.isNaN(p.v))
            .map(p => ({
              time: Math.floor(p.ts) as Time,
              value: p.v,
              color: withOpacity(p.color ?? line.color, line.opacity),
            }));
          s.setData(pts);
          this.overlaySeries.push(s);
        } else {
          const s = this.chart.addSeries(LineSeries, {
            color: withOpacity(line.color, line.opacity),
            lineWidth: line.lineWidth ?? 1,
            lineStyle: LINE_STYLE[line.lineStyle ?? 'solid'],
            priceLineVisible: false,
            title: line.label,
          }, idx);
          const pts: LineData[] = line.points
            .filter(p => p.v !== null && !Number.isNaN(p.v))
            .map(p => ({ time: Math.floor(p.ts) as Time, value: p.v }));
          s.setData(pts);
          this.overlaySeries.push(s);
        }
      }
    }

    // Give the main price pane more vertical room than oscillator panes.
    const panes = this.chart.panes();
    if (panes.length > 1) {
      panes[0].setStretchFactor(3);
      for (let i = 1; i < panes.length; i++) panes[i].setStretchFactor(1);
    }

    /* Auto-fit only when the caller signals a new series via
       [seriesKey]. Live appends and trailing-window trims (which
       change [candles[0].ts] but not the logical series) preserve
       the current pan/zoom. */
    const key = this.seriesKey();
    if (key && key !== this.lastFittedKey && candles.length > 0) {
      console.warn(
        `[chart] fitContent: seriesKey ${this.lastFittedKey} → ${key}, ` +
        `len=${candles.length}`);
      this.chart.timeScale().fitContent();
      this.clearMeasure();
      this.lastFittedKey = key;
    } else {
      console.debug(
        `[chart] render (no fit): key=${key}, len=${candles.length}`);
    }
  }
}
