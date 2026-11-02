import { Location } from '@angular/common';
import { inject } from '@angular/core';
import { RedirectCommand, Router, type CanActivateFn } from '@angular/router';
import { ApiService } from './api.service';
import { NotifyService } from './ui';

function selectedWishlistId(): string | null {
  const router = inject(Router);
  const state: unknown = router.currentNavigation()?.extras.state ?? inject(Location).getState();
  if (typeof state !== 'object' || state === null || !('wishlistId' in state)) return null;
  return typeof state.wishlistId === 'string' && state.wishlistId.length > 0 ? state.wishlistId : null;
}

export const legacyWishlistRedirect: CanActivateFn = async (route) => {
  const router = inject(Router);
  const api = inject(ApiService);
  const notify = inject(NotifyService);
  const id = route.paramMap.get('id') ?? selectedWishlistId();
  if (!id) return router.createUrlTree(['/wishlists']);
  try {
    const wishlist = await api.getWishlist(id);
    return new RedirectCommand(router.createUrlTree(['/s', wishlist.shareToken]), { replaceUrl: true });
  } catch (error) {
    await notify.error(error);
    return router.createUrlTree(['/wishlists']);
  }
};
