import { Component, OnDestroy, OnInit, computed, effect, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { firstValueFrom, timeout } from 'rxjs';

interface BackendState {
  name: string;
  live: boolean | null;
  message: string;
  ms: number | null;
}

interface HistoryRow {
  service: string;
  status: string;
  created_at: string;
}

// one status check: did it answer, and how long it took
interface Sample {
  live: boolean;
  ms: number;
}

// one poll of all backends: sequence number, time, and the response time of each live one
interface Poll {
  seq: number;
  t: number;
  ms: Record<string, number | null>;
}

// response time over one bucket of polls: first, highest, lowest, last
interface Candle {
  key: number;
  t: number;
  open: number;
  high: number;
  low: number;
  close: number;
  n: number;
}

interface TipRow {
  label: string;
  value: string;
  color?: string;
}

interface Tip {
  title: string;
  rows: TipRow[];
}

interface PieItem {
  name: string;
  color: string;
  value: number;
  text: string;
}

interface Theme {
  id: string;
  name: string;
  accent: string;
  accent2: string;
  soft: string;
}

// all dark: a gradient from accent to accent2; soft is a lighter tint of the accent, for text on the dark surface
const THEMES: Theme[] = [
  { id: 'emerald', name: 'Emerald', accent: '#10b981', accent2: '#0d9488', soft: '#6ee7b7' },
  { id: 'ocean', name: 'Ocean', accent: '#0ea5e9', accent2: '#2563eb', soft: '#7dd3fc' },
  { id: 'kubernetes', name: 'Kubernetes', accent: '#326ce5', accent2: '#06b6d4', soft: '#93c5fd' },
  { id: 'indigo', name: 'Indigo', accent: '#6366f1', accent2: '#8b5cf6', soft: '#a5b4fc' },
  { id: 'violet', name: 'Violet', accent: '#8b5cf6', accent2: '#ec4899', soft: '#c4b5fd' },
  { id: 'fuchsia', name: 'Fuchsia', accent: '#d946ef', accent2: '#f43f5e', soft: '#f0abfc' },
  { id: 'candy', name: 'Candy', accent: '#f472b6', accent2: '#60a5fa', soft: '#f9a8d4' },
  { id: 'rose', name: 'Rose', accent: '#f43f5e', accent2: '#a855f7', soft: '#fda4af' },
  { id: 'sunset', name: 'Sunset', accent: '#f97316', accent2: '#ec4899', soft: '#fdba74' },
  { id: 'ember', name: 'Ember', accent: '#f97316', accent2: '#dc2626', soft: '#fed7aa' },
  { id: 'lava', name: 'Lava', accent: '#ef4444', accent2: '#f59e0b', soft: '#fca5a5' },
  { id: 'harvest', name: 'Harvest', accent: '#f59e0b', accent2: '#84cc16', soft: '#fcd34d' },
  { id: 'honey', name: 'Honey', accent: '#eab308', accent2: '#f97316', soft: '#fde047' },
  { id: 'meadow', name: 'Meadow', accent: '#84cc16', accent2: '#22c55e', soft: '#bef264' },
  { id: 'lagoon', name: 'Lagoon', accent: '#22c55e', accent2: '#0ea5e9', soft: '#86efac' },
  { id: 'peacock', name: 'Peacock', accent: '#06b6d4', accent2: '#22c55e', soft: '#67e8f9' },
  { id: 'glacier', name: 'Glacier', accent: '#14b8a6', accent2: '#3b82f6', soft: '#5eead4' },
  { id: 'aurora', name: 'Aurora', accent: '#22d3ee', accent2: '#a78bfa', soft: '#a5f3fc' },
  { id: 'plum', name: 'Plum', accent: '#c026d3', accent2: '#4f46e5', soft: '#e879f9' },
  { id: 'steel', name: 'Steel', accent: '#94a3b8', accent2: '#38bdf8', soft: '#cbd5e1' },
];
const THEME_KEY = 'theme';

// the saved choice, else the first theme; storage can be blocked, so every access is guarded
function initialTheme(): string {
  try {
    const saved = localStorage.getItem(THEME_KEY);
    return THEMES.find((t) => t.id === saved)?.id ?? THEMES[0].id;
  } catch {
    return THEMES[0].id;
  }
}

// a over b, as hex: the page background and browser chrome take the same tint the component mixes in CSS
function mix(a: string, b: string, pct: number) {
  const ch = (hex: string, i: number) => parseInt(hex.slice(1 + i * 2, 3 + i * 2), 16);
  return (
    '#' +
    [0, 1, 2]
      .map((i) => Math.round((ch(a, i) * pct + ch(b, i) * (100 - pct)) / 100).toString(16).padStart(2, '0'))
      .join('')
  );
}

const BACKENDS = ['backend1', 'backend2', 'backend3', 'backend4'];
const COLORS = ['#326ce5', '#0d9488', '#7c3aed', '#d97706'];
const POLL_MS = 5000;
const MAX_SAMPLES = 30;
const SPARK = { w: 120, h: 34 };
const CHART = { w: 600, h: 170 };
const BUCKET = 6; // polls per candle, 30 s
const CANDLES = 20;
const KEEP = (CANDLES + 1) * BUCKET;
const PIE = { c: 60, outer: 56, inner: 36 };

const mean = (values: number[]) =>
  values.length ? Math.round(values.reduce((a, b) => a + b, 0) / values.length) : null;

// groups polls by absolute sequence number, so a candle keeps its shape as old polls drop off
function toCandles(points: { seq: number; t: number; v: number }[]): Candle[] {
  const buckets = new Map<number, typeof points>();
  for (const p of points) {
    const key = Math.floor(p.seq / BUCKET);
    const bucket = buckets.get(key) ?? [];
    bucket.push(p);
    buckets.set(key, bucket);
  }
  return [...buckets.entries()].slice(-CANDLES).map(([key, b]) => {
    const v = b.map((p) => p.v);
    return { key, t: b[0].t, open: v[0], high: Math.max(...v), low: Math.min(...v), close: v[v.length - 1], n: v.length };
  });
}

// ring segment from angle a0 to a1, with a 2px gap on each side unless it is the only one
function ring(a0: number, a1: number, alone: boolean) {
  const { c, outer, inner } = PIE;
  const gapO = alone ? 0 : 1 / outer;
  const gapI = alone ? 0 : 1 / inner;
  const at = (r: number, a: number) => `${(c + r * Math.cos(a)).toFixed(2)},${(c + r * Math.sin(a)).toFixed(2)}`;
  const large = a1 - a0 > Math.PI ? 1 : 0;
  return (
    `M${at(outer, a0 + gapO)}A${outer},${outer} 0 ${large} 1 ${at(outer, a1 - gapO)}` +
    `L${at(inner, a1 - gapI)}A${inner},${inner} 0 ${large} 0 ${at(inner, a0 + gapI)}Z`
  );
}

function pie(title: string, sub: string, center: { value: string; label: string }, items: PieItem[], unit: string) {
  const total = items.reduce((t, i) => t + i.value, 0);
  const shown = items.filter((i) => i.value > 0);
  let angle = -Math.PI / 2;
  const slices = shown.map((i) => {
    const sweep = shown.length === 1 ? 2 * Math.PI - 0.001 : (i.value / total) * 2 * Math.PI;
    const d = ring(angle, angle + sweep, shown.length === 1);
    angle += sweep;
    return { name: i.name, color: i.color, d, tip: tipFor(i, total, unit) };
  });
  const legend = items.map((i) => ({
    name: i.name,
    color: i.color,
    text: i.value > 0 ? i.text : '-',
    share: total ? Math.round((i.value / total) * 1000) / 10 : 0,
  }));
  return { title, sub, center, slices, legend };
}

function tipFor(i: PieItem, total: number, unit: string): Tip {
  const share = Math.round((i.value / total) * 1000) / 10;
  return {
    title: i.name,
    rows: [
      { label: unit, value: i.text, color: i.color },
      { label: 'share', value: `${share}%` },
    ],
  };
}

// right-aligned polyline for the response times; a failed check breaks the line
function plot(samples: Sample[], w: number, h: number, max: number) {
  const step = w / (MAX_SAMPLES - 1);
  const pad = 3;
  let line = '';
  let area = '';
  let run: string[] = [];
  const flush = () => {
    if (run.length) {
      const first = run[0].split(',')[0];
      const last = run[run.length - 1].split(',')[0];
      line += 'M' + run.join('L');
      area += `M${first},${h}L${run.join('L')}L${last},${h}Z`;
    }
    run = [];
  };
  samples.forEach((s, i) => {
    if (!s.live) return flush();
    const x = (w - (samples.length - 1 - i) * step).toFixed(1);
    const y = (h - pad - (s.ms / max) * (h - 2 * pad)).toFixed(1);
    run.push(`${x},${y}`);
  });
  flush();
  return { line, area };
}

@Component({
  selector: 'app-root',
  imports: [DatePipe],
  templateUrl: './app.html',
  styleUrl: './app.css',
  host: {
    '[style.--accent]': 'current().accent',
    '[style.--accent-2]': 'current().accent2',
    '[style.--accent-soft]': 'current().soft',
  },
})
export class App implements OnInit, OnDestroy {
  private readonly http = inject(HttpClient);
  private timer?: ReturnType<typeof setInterval>;
  private pollSeq = 0;

  protected readonly themes = THEMES;
  protected readonly themeId = signal(initialTheme());
  protected readonly current = computed(() => THEMES.find((t) => t.id === this.themeId()) ?? THEMES[0]);

  constructor() {
    // page background and browser chrome follow the theme too, not just the component
    effect(() => {
      const theme = this.current();
      const bg = mix(mix(theme.accent, theme.accent2, 50), '#060a09', 10);
      document.documentElement.style.background = bg;
      document.querySelector('meta[name="theme-color"]')?.setAttribute('content', bg);
      try {
        localStorage.setItem(THEME_KEY, theme.id);
      } catch {
        // private mode: the choice just is not remembered
      }
    });
  }

  protected readonly backends = signal<BackendState[]>(
    BACKENDS.map((name) => ({ name, live: null, message: 'checking...', ms: null })),
  );

  protected readonly history = signal<HistoryRow[]>([]);

  // the last MAX_SAMPLES checks of each backend, kept in the browser for the graphs
  private readonly series = signal<Record<string, Sample[]>>({});

  protected readonly liveCount = computed(() => this.backends().filter((b) => b.live).length);

  protected readonly healthyPercent = computed(() =>
    Math.round((this.liveCount() / this.backends().length) * 100),
  );

  protected readonly averageMs = computed(() => {
    const times = this.backends().flatMap((b) => (b.live && b.ms !== null ? [b.ms] : []));
    return times.length ? Math.round(times.reduce((a, b) => a + b, 0) / times.length) : null;
  });

  protected readonly checks = computed(() =>
    Object.values(this.series()).reduce((total, s) => total + s.length, 0),
  );

  protected readonly uptimePercent = computed(() => {
    const all = Object.values(this.series()).flat();
    return all.length ? Math.round((all.filter((s) => s.live).length / all.length) * 1000) / 10 : null;
  });

  protected readonly maxMs = computed(() =>
    Math.max(50, ...Object.values(this.series()).flatMap((s) => s.filter((x) => x.live).map((x) => x.ms))),
  );

  protected readonly charts = computed(() => {
    const series = this.series();
    const maxAll = this.maxMs();
    return BACKENDS.map((name, i) => {
      const samples = series[name] ?? [];
      const own = Math.max(50, ...samples.filter((s) => s.live).map((s) => s.ms));
      return {
        name,
        color: COLORS[i],
        ticks: samples.map((s) => s.live),
        spark: plot(samples, SPARK.w, SPARK.h, own),
        chart: plot(samples, CHART.w, CHART.h, maxAll),
      };
    });
  });

  // the last KEEP polls, kept in the browser for the candlesticks
  private readonly polls = signal<Poll[]>([]);

  protected readonly pies = computed(() => {
    const rows = this.history();
    const series = this.series();
    const checks = BACKENDS.map((name, i) => {
      const own = rows.filter((r) => r.service === name);
      const live = own.filter((r) => r.status === 'live').length;
      return { name, color: COLORS[i], value: own.length, text: `${own.length} (${live} live)` };
    });
    const times = BACKENDS.map((name, i) => {
      const avg = mean((series[name] ?? []).filter((s) => s.live).map((s) => s.ms)) ?? 0;
      return { name, color: COLORS[i], value: avg, text: `${avg} ms` };
    });
    const avgAll = mean(times.filter((t) => t.value > 0).map((t) => t.value));
    return [
      pie('Recent checks by service', 'Rows in the history table', { value: String(rows.length), label: 'checks' }, checks, 'checks'),
      pie('Average response by backend', 'Share of the summed averages', { value: String(avgAll ?? '-'), label: 'ms avg' }, times, 'average'),
    ];
  });

  protected readonly candleCharts = computed(() => {
    const polls = this.polls();
    const views = [
      { name: 'All backends', value: (p: Poll) => mean(Object.values(p.ms).filter((v): v is number => v !== null)) },
      ...BACKENDS.map((name) => ({ name, value: (p: Poll) => p.ms[name] ?? null })),
    ];
    return views.map((view) => {
      const points = polls.flatMap((p) => {
        const v = view.value(p);
        return v === null ? [] : [{ seq: p.seq, t: p.t, v }];
      });
      const candles = toCandles(points);
      const lo = Math.min(...candles.map((c) => c.low));
      const hi = Math.max(...candles.map((c) => c.high));
      const min = candles.length ? Math.max(0, Math.floor(lo * 0.9)) : 0;
      const max = candles.length ? Math.max(min + 10, Math.ceil(hi * 1.1)) : 100;
      const top = (v: number) => ((max - v) / (max - min)) * 100;
      const time = (t: number) => new Date(t).toLocaleTimeString([], { hour12: false });
      const cells = candles.map((c) => {
        const dir = c.close > c.open ? 'slow' : c.close < c.open ? 'fast' : 'flat';
        const tip: Tip = {
          title: `${view.name} · ${time(c.t)}`,
          rows: [
            { label: 'open', value: `${c.open} ms` },
            { label: 'high', value: `${c.high} ms` },
            { label: 'low', value: `${c.low} ms` },
            { label: 'close', value: `${c.close} ms` },
            { label: dir === 'slow' ? 'slower' : dir === 'fast' ? 'faster' : 'unchanged', value: `${c.n} polls` },
          ],
        };
        const text = `${c.open} → ${c.close} · ${c.low}–${c.high}`;
        return { key: c.key, t: c.t, dir, wickTop: top(c.high), wickH: top(c.low) - top(c.high), bodyTop: top(Math.max(c.open, c.close)), bodyH: Math.abs(top(c.open) - top(c.close)), tip, text };
      });
      const last = candles[candles.length - 1];
      return {
        name: view.name,
        cells: [...Array<null>(CANDLES - cells.length).fill(null), ...cells],
        ticks: [0, 50, 100].map((pct) => ({ top: pct, label: String(Math.round(max - ((max - min) * pct) / 100)) })),
        start: CANDLES - candles.length,
        from: candles.length >= 7 ? time(candles[0].t) : '',
        to: last ? time(last.t) : '',
        summary: last ? `close ${last.close} ms` : 'collecting data',
      };
    });
  });

  protected readonly candleTable = computed(() => {
    const charts = this.candleCharts();
    const keys = [...new Set(charts.flatMap((c) => c.cells.flatMap((x) => (x ? [x.key] : []))))].sort((a, b) => a - b);
    return keys.map((key) => {
      const found = charts.map((c) => c.cells.find((x) => x?.key === key));
      return { key, t: found.find((x) => x)?.t ?? 0, cells: found.map((x) => x?.text ?? '-') };
    });
  });

  protected pick(id: string) {
    this.themeId.set(id);
  }

  protected dot(t: Theme) {
    return `linear-gradient(135deg, ${t.accent}, ${t.accent2})`;
  }

  // one tooltip for all charts: follows the pointer, or sits above the focused mark
  protected readonly tip = signal<{ left: number; top: number; tip: Tip } | null>(null);

  protected showTip(event: PointerEvent | FocusEvent, tip: Tip) {
    let x: number;
    let y: number;
    if (event instanceof FocusEvent) {
      const r = (event.currentTarget as Element).getBoundingClientRect();
      x = r.left + r.width / 2;
      y = r.top;
    } else {
      x = event.clientX;
      y = event.clientY;
    }
    this.tip.set({ left: Math.max(8, Math.min(x + 14, window.innerWidth - 232)), top: y + 14, tip });
  }

  protected hideTip() {
    this.tip.set(null);
  }

  protected readonly spark = SPARK;
  protected readonly chart = CHART;
  protected readonly maxSamples = MAX_SAMPLES;

  ngOnInit() {
    this.refresh();
    this.timer = setInterval(() => this.refresh(), POLL_MS);
  }

  ngOnDestroy() {
    clearInterval(this.timer);
  }

  // cards lean towards the pointer
  protected tilt(event: PointerEvent) {
    const el = event.currentTarget as HTMLElement;
    const r = el.getBoundingClientRect();
    const x = (event.clientX - r.left) / r.width - 0.5;
    const y = (event.clientY - r.top) / r.height - 0.5;
    el.style.setProperty('--ry', `${(x * 14).toFixed(1)}deg`);
    el.style.setProperty('--rx', `${(-y * 14).toFixed(1)}deg`);
  }

  protected untilt(event: PointerEvent) {
    const el = event.currentTarget as HTMLElement;
    el.style.removeProperty('--ry');
    el.style.removeProperty('--rx');
  }

  private async refresh() {
    const states = await Promise.all(BACKENDS.map((name) => this.check(name)));
    this.backends.set(states);
    const ms = Object.fromEntries(states.map((b) => [b.name, b.live ? b.ms : null]));
    this.polls.update((polls) => [...polls, { seq: this.pollSeq++, t: Date.now(), ms }].slice(-KEEP));
    this.series.update((series) =>
      Object.fromEntries(
        states.map((b) => [
          b.name,
          [...(series[b.name] ?? []), { live: !!b.live, ms: b.ms ?? 0 }].slice(-MAX_SAMPLES),
        ]),
      ),
    );
    await this.loadHistory(states.find((b) => b.live)?.name);
  }

  // history lives in Postgres, so any live backend can serve all services' rows
  private async loadHistory(via?: string) {
    if (!via) return;
    try {
      const rows = await firstValueFrom(
        this.http
          .get<HistoryRow[]>(`/api/${via}/history`, { params: { service: 'all', limit: 20 } })
          .pipe(timeout(3000)),
      );
      this.history.set(rows);
    } catch {
      // keep previous rows
    }
  }

  private async check(name: string): Promise<BackendState> {
    const start = performance.now();
    try {
      const res = await firstValueFrom(
        this.http.get<{ message: string }>(`/api/${name}/status`).pipe(timeout(3000)),
      );
      return { name, live: true, message: res.message, ms: Math.round(performance.now() - start) };
    } catch {
      return { name, live: false, message: `${name} off`, ms: null };
    }
  }
}
