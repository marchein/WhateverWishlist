import { TestBed } from '@angular/core/testing';
import { version } from '../../../../package.json';
import { API_URL, ApiService } from '../../core/api.service';
import { NotifyService } from '../../core/ui';
import { StatusPage } from './status.page';

describe('StatusPage', () => {
  const health = vi.fn();
  const error = vi.fn();
  let page: StatusPage;

  beforeEach(() => {
    health.mockReset();
    error.mockReset();
    TestBed.configureTestingModule({
      providers: [
        { provide: ApiService, useValue: { health } },
        { provide: NotifyService, useValue: { error } },
      ],
    });
    page = TestBed.runInInjectionContext(() => new StatusPage());
  });

  it('shows the bundled frontend version and the actual API address', () => {
    expect(page.frontendVersion).toBe(version);
    expect(page.backendAddress).toBe(new URL(API_URL, window.location.origin).href);
  });

  it('checks the live backend on entry', async () => {
    health.mockResolvedValue({ ok: true, version: 'v2.3.4' });
    await page.load();
    expect(page.backendVersion()).toBe('v2.3.4');
    expect(page.loading()).toBe(false);
    expect(page.failed()).toBe(false);
  });

  it('does not invent a version for an older backend', async () => {
    health.mockResolvedValue({ ok: true });
    await page.load();
    expect(page.backendVersion()).toBeNull();
    expect(page.failed()).toBe(false);
  });

  it('clears stale versions on failure and supports retry', async () => {
    health.mockResolvedValueOnce({ ok: true, version: 'old' });
    await page.load();
    const failure = new Error('Offline');
    health.mockRejectedValueOnce(failure);
    await page.load();
    expect(page.backendVersion()).toBeNull();
    expect(page.failed()).toBe(true);
    expect(error).toHaveBeenCalledWith(failure);
    health.mockResolvedValueOnce({ ok: true, version: 'new' });
    await page.load();
    expect(page.backendVersion()).toBe('new');
    expect(page.failed()).toBe(false);
  });

  it('rejects an unhealthy backend response', async () => {
    health.mockResolvedValue({ ok: false, version: 'broken' });
    await page.load();
    expect(page.backendVersion()).toBeNull();
    expect(page.failed()).toBe(true);
    expect(error).toHaveBeenCalled();
  });
});
