import { Component, OnDestroy, OnInit, computed, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { firstValueFrom, timeout } from 'rxjs';

interface BackendState {
  name: string;
  live: boolean | null;
  message: string;
}

interface HistoryRow {
  service: string;
  status: string;
  created_at: string;
}

const BACKENDS = ['backend1', 'backend2', 'backend3', 'backend4'];
const POLL_MS = 5000;
const MAX_TILT = 9;

// Digital-rain columns. Generated once from a fixed seed so every render is identical.
const GLYPHS = 'ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789:.=*+-<>|';

interface RainColumn {
  x: number;
  size: number;
  duration: number;
  delay: number;
  opacity: number;
  text: string;
}

function buildRain(columns: number, length: number): RainColumn[] {
  let seed = 20260514;
  const next = () => {
    seed = (seed * 1664525 + 1013904223) % 4294967296;
    return seed / 4294967296;
  };
  return Array.from({ length: columns }, (_, i) => ({
    x: (i / columns) * 100 + next() * (100 / columns) * 0.6,
    size: 12 + Math.floor(next() * 8),
    duration: 7 + next() * 11,
    delay: -next() * 18,
    opacity: 0.35 + next() * 0.65,
    text: Array.from({ length }, () => GLYPHS[Math.floor(next() * GLYPHS.length)]).join('\n'),
  }));
}

@Component({
  selector: 'app-root',
  imports: [DatePipe],
  templateUrl: './app.html',
  styleUrl: './app.css',
})
export class App implements OnInit, OnDestroy {
  private readonly http = inject(HttpClient);
  private timer?: ReturnType<typeof setInterval>;

  protected readonly backends = signal<BackendState[]>(
    BACKENDS.map((name) => ({ name, live: null, message: 'checking...' })),
  );

  protected readonly history = signal<HistoryRow[]>([]);

  protected readonly rain = buildRain(44, 26);

  protected readonly liveCount = computed(() => this.backends().filter((b) => b.live).length);

  // 3D tilt: rotate the card towards the pointer, up to MAX_TILT degrees
  protected tilt(event: PointerEvent) {
    const wrapper = event.currentTarget as HTMLElement;
    const card = wrapper.firstElementChild as HTMLElement | null;
    if (!card) return;
    const box = wrapper.getBoundingClientRect();
    const x = (event.clientX - box.left) / box.width - 0.5;
    const y = (event.clientY - box.top) / box.height - 0.5;
    card.style.setProperty('--ry', `${(x * MAX_TILT * 2).toFixed(1)}deg`);
    card.style.setProperty('--rx', `${(-y * MAX_TILT * 2).toFixed(1)}deg`);
  }

  protected resetTilt(event: PointerEvent) {
    const card = (event.currentTarget as HTMLElement).firstElementChild as HTMLElement | null;
    card?.style.setProperty('--rx', '0deg');
    card?.style.setProperty('--ry', '0deg');
  }

  ngOnInit() {
    this.refresh();
    this.timer = setInterval(() => this.refresh(), POLL_MS);
  }

  ngOnDestroy() {
    clearInterval(this.timer);
  }

  private async refresh() {
    const states = await Promise.all(BACKENDS.map((name) => this.check(name)));
    this.backends.set(states);
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
    try {
      const res = await firstValueFrom(
        this.http.get<{ message: string }>(`/api/${name}/status`).pipe(timeout(3000)),
      );
      return { name, live: true, message: res.message };
    } catch {
      return { name, live: false, message: `${name} off` };
    }
  }
}
