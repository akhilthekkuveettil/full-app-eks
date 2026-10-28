import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { App } from './app';

// lets the component's pending promise chain (status checks -> history request) settle
const tick = () => new Promise<void>((resolve) => setTimeout(resolve));

describe('App', () => {
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    http = TestBed.inject(HttpTestingController);
  });

  it('shows a live backend and marks failing ones off', async () => {
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();

    http.expectOne('/api/backend1/status').flush({ message: 'backend1 live' });
    for (const name of ['backend2', 'backend3', 'backend4']) {
      http.expectOne(`/api/${name}/status`).flush('err', { status: 500, statusText: 'err' });
    }
    await tick();
    http.match((req) => req.url === '/api/backend1/history').forEach((r) => r.flush([]));
    await tick();
    fixture.detectChanges();

    const cards = Array.from<HTMLElement>(fixture.nativeElement.querySelectorAll('.card'));
    expect(cards.map((c) => c.textContent?.trim())).toEqual([
      'backend1 live',
      'backend2 off',
      'backend3 off',
      'backend4 off',
    ]);
    expect(cards[0].classList.contains('live')).toBe(true);
    expect(cards[1].classList.contains('off')).toBe(true);
  });

  it('renders history rows from the first live backend', async () => {
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();

    for (const name of ['backend1', 'backend2', 'backend3', 'backend4']) {
      http.expectOne(`/api/${name}/status`).flush({ message: `${name} live` });
    }
    await tick();
    http
      .expectOne((req) => req.url === '/api/backend1/history')
      .flush([{ service: 'backend2', status: 'live', created_at: '2026-01-01T00:00:00Z' }]);
    await tick();
    fixture.detectChanges();

    const row = fixture.nativeElement.querySelector('tbody tr') as HTMLElement;
    expect(row.textContent).toContain('backend2');
    expect(row.textContent).toContain('live');
  });

  it('switches between the light and dark theme', async () => {
    const fixture = TestBed.createComponent(App);
    fixture.detectChanges();
    const host = fixture.nativeElement as HTMLElement;
    const toggle = host.querySelector('.theme-toggle') as HTMLButtonElement;

    expect(host.getAttribute('data-theme')).toBe('light');
    expect(toggle.getAttribute('aria-checked')).toBe('false');

    toggle.click();
    fixture.detectChanges();
    expect(host.getAttribute('data-theme')).toBe('dark');
    expect(toggle.getAttribute('aria-checked')).toBe('true');
    expect(document.documentElement.dataset['theme']).toBe('dark');
  });
});
