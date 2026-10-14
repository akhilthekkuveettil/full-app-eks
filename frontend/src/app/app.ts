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
