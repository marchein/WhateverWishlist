import { Routes } from '@angular/router';
import { authGuard } from './core/auth.interceptor';
import { legacyWishlistRedirect } from './core/wishlist-navigation';

export const routes: Routes = [
  { path: '', redirectTo: 'wishlists', pathMatch: 'full' },
  {
    path: 'login',
    loadComponent: () => import('./pages/login/login.page').then((m) => m.LoginPage),
  },
  {
    path: 'wishlists',
    canActivate: [authGuard],
    loadComponent: () => import('./pages/wishlists/wishlists.page').then((m) => m.WishlistsPage),
  },
  {
    path: 'wishlists/:id',
    canActivate: [authGuard, legacyWishlistRedirect],
    children: [],
  },
  {
    path: 'manage/wishlist',
    canActivate: [authGuard, legacyWishlistRedirect],
    children: [],
  },
  {
    path: 'status',
    loadComponent: () =>
      import('./pages/status/status.page').then((m) => m.StatusPage),
  },
  {
    // Public share link – works for guests and registered users alike.
    path: 's/:token',
    loadComponent: () =>
      import('./pages/shared-wishlist/shared-wishlist.page').then((m) => m.SharedWishlistPage),
  },
  { path: '**', redirectTo: 'wishlists' },
];
