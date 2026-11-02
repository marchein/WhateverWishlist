import { Location } from '@angular/common';
import { Component, input } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { Router, provideRouter, withComponentInputBinding } from '@angular/router';
import { RouterTestingHarness } from '@angular/router/testing';
import { routes } from '../app.routes';
import { ApiService } from './api.service';
import { AuthService } from './auth.service';
import { NotifyService } from './ui';

@Component({ template: '{{ token() }}' })
class WishlistStubComponent {
  readonly token = input<string>();
}

describe('Canonical wishlist navigation', () => {
  const isLoggedIn = vi.fn();
  const getWishlist = vi.fn();
  const error = vi.fn();

  beforeEach(() => {
    isLoggedIn.mockReturnValue(true);
    getWishlist.mockReset().mockResolvedValue({ shareToken: 'existing-token' });
    error.mockReset();
    TestBed.configureTestingModule({
      providers: [
        { provide: AuthService, useValue: { isLoggedIn } },
        { provide: ApiService, useValue: { getWishlist } },
        { provide: NotifyService, useValue: { error } },
        provideRouter(routes.map((route) => ({
          ...route,
          loadComponent: route.loadComponent ? () => Promise.resolve(WishlistStubComponent) : undefined,
        })), withComponentInputBinding()),
      ],
    });
  });

  it('uses the same existing share address for owners and guests', async () => {
    const harness = await RouterTestingHarness.create('/s/existing-token');
    expect(harness.routeNativeElement?.textContent).toBe('existing-token');
    expect(TestBed.inject(Router).url).toBe('/s/existing-token');
    expect(getWishlist).not.toHaveBeenCalled();
    isLoggedIn.mockReturnValue(false);
    await harness.navigateByUrl('/s/another-existing-token');
    expect(TestBed.inject(Router).url).toBe('/s/another-existing-token');
    expect(harness.routeNativeElement?.textContent).toBe('another-existing-token');
  });

  it('preserves old private bookmarks by resolving their current share token', async () => {
    await RouterTestingHarness.create('/wishlists/old-id');
    expect(getWishlist).toHaveBeenCalledWith('old-id');
    expect(TestBed.inject(Router).url).toBe('/s/existing-token');
  });

  it('requires authentication before resolving old private bookmarks', async () => {
    isLoggedIn.mockReturnValue(false);
    await RouterTestingHarness.create('/wishlists/private-id');
    expect(TestBed.inject(Router).url).toBe('/login?returnUrl=%2Fwishlists%2Fprivate-id');
    expect(getWishlist).not.toHaveBeenCalled();
  });

  it('reports an unauthorized or deleted legacy wishlist instead of exposing it', async () => {
    const failure = new Error('Wishlist not found');
    getWishlist.mockRejectedValue(failure);
    await RouterTestingHarness.create('/wishlists/not-owned');
    expect(error).toHaveBeenCalledWith(failure);
    expect(TestBed.inject(Router).url).toBe('/wishlists');
  });

  it('redirects the former history-state editor to the share address', async () => {
    vi.spyOn(TestBed.inject(Location), 'getState').mockReturnValue({ wishlistId: 'restored-id' });
    await RouterTestingHarness.create('/manage/wishlist');
    expect(getWishlist).toHaveBeenCalledWith('restored-id');
    expect(TestBed.inject(Router).url).toBe('/s/existing-token');
  });

  it('sends an old editor address without a selection to the overview', async () => {
    await RouterTestingHarness.create('/manage/wishlist');
    expect(TestBed.inject(Router).url).toBe('/wishlists');
    expect(getWishlist).not.toHaveBeenCalled();
  });

  it('keeps public wishlist and status routes unguarded', () => {
    expect(routes.find((route) => route.path === 's/:token')?.canActivate).toBeUndefined();
    expect(routes.find((route) => route.path === 'status')?.canActivate).toBeUndefined();
  });
});
