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

type Theme = 'light' | 'dark';
const THEME_KEY = 'theme';

// the saved choice, else light; storage can be blocked, so every access is guarded
function initialTheme(): Theme {
  try {
    return localStorage.getItem(THEME_KEY) === 'dark' ? 'dark' : 'light';
  } catch {
    return 'light';
  }
}

const BACKENDS = ['backend1', 'backend2', 'backend3', 'backend4'];
const COLORS = ['#326ce5', '#0d9488', '#7c3aed', '#d97706'];
const POLL_MS = 5000;
const MAX_SAMPLES = 30;
const SPARK = { w: 120, h: 34 };
const CHART = { w: 600, h: 170 };

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
  host: { '[attr.data-theme]': 'theme()' },
})
export class App implements OnInit, OnDestroy {
  private readonly http = inject(HttpClient);
  private timer?: ReturnType<typeof setInterval>;

  protected readonly backends = signal<BackendState[]>(
    BACKENDS.map((name) => ({ name, live: null, message: 'checking...', ms: null })),
  );

  protected readonly history = signal<HistoryRow[]>([]);

  protected readonly theme = signal<Theme>(initialTheme());

  constructor() {
    // page background and browser chrome follow the theme too, not just the component
    effect(() => {
      const theme = this.theme();
      document.documentElement.dataset['theme'] = theme;
      document
        .querySelector('meta[name="theme-color"]')
        ?.setAttribute('content', theme === 'dark' ? '#0a1020' : '#f4f7fd');
      try {
        localStorage.setItem(THEME_KEY, theme);
      } catch {
        // private mode: the choice just is not remembered
      }
    });
  }

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

  protected toggleTheme() {
    this.theme.update((t) => (t === 'dark' ? 'light' : 'dark'));
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
