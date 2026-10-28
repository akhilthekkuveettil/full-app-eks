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
