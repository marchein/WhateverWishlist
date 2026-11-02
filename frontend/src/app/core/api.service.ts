import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { firstValueFrom, timeout, type Observable } from 'rxjs';
import { environment } from '../../environments/environment';
import type {
  AuthResponse,
  Item,
  ItemInput,
  ScrapeResult,
  SharedItem,
  SharedWishlist,
  User,
  Wishlist,
  WishlistInput,
  WishlistWithItems,
} from './models';

export const API_URL = `${environment.apiBaseUrl}/api`;

@Injectable({ providedIn: 'root' })
export class ApiService {
  private readonly http = inject(HttpClient);

  private get<T>(path: string) {
    return this.call(this.http.get<T>(`${API_URL}${path}`));
  }
  private post<T>(path: string, body: unknown = {}) {
    return this.call(this.http.post<T>(`${API_URL}${path}`, body));
  }
  private patch<T>(path: string, body: unknown) {
    return this.call(this.http.patch<T>(`${API_URL}${path}`, body));
  }
  private delete(path: string) {
    return this.call(this.http.delete<void>(`${API_URL}${path}`));
  }
  private call<T>(request: Observable<T>): Promise<T> {
    return firstValueFrom(request);
  }

  // Auth
  health() {
    return this.call(this.http.get<{ ok: boolean; version?: string }>(`${API_URL}/health`).pipe(timeout(10_000)));
  }

  register(email: string, password: string, displayName: string) {
    return this.post<AuthResponse>('/auth/register', { email, password, displayName });
  }
  login(email: string, password: string) {
    return this.post<AuthResponse>('/auth/login', { email, password });
  }
  me() {
    return this.get<User>('/auth/me');
  }

  // Own wishlists
  listWishlists() {
    return this.get<Wishlist[]>('/wishlists');
  }
  createWishlist(input: WishlistInput) {
    return this.post<Wishlist>('/wishlists', input);
  }
  getWishlist(id: string) {
    return this.get<WishlistWithItems>(`/wishlists/${encodeURIComponent(id)}`);
  }
  updateWishlist(id: string, input: Partial<WishlistInput>) {
    return this.patch<Wishlist>(`/wishlists/${encodeURIComponent(id)}`, input);
  }
  deleteWishlist(id: string) {
    return this.delete(`/wishlists/${encodeURIComponent(id)}`);
  }
  regenerateShareToken(id: string) {
    return this.post<Wishlist>(`/wishlists/${encodeURIComponent(id)}/share-token`);
  }
  createItem(wishlistId: string, input: ItemInput) {
    return this.post<Item>(`/wishlists/${encodeURIComponent(wishlistId)}/items`, input);
  }
  updateItem(wishlistId: string, itemId: string, input: Partial<ItemInput>) {
    return this.patch<Item>(`/wishlists/${encodeURIComponent(wishlistId)}/items/${encodeURIComponent(itemId)}`, input);
  }
  deleteItem(wishlistId: string, itemId: string) {
    return this.delete(`/wishlists/${encodeURIComponent(wishlistId)}/items/${encodeURIComponent(itemId)}`);
  }

  // Helpers for adding items
  scrape(input: string) {
    return this.post<ScrapeResult>('/scrape', { input });
  }
  uploadImage(file: File) {
    const form = new FormData();
    form.append('image', file);
    return this.post<{ url: string }>('/uploads', form);
  }

  // Shared (public) wishlists
  getShared(token: string) {
    return this.get<SharedWishlist>(`/shared/${encodeURIComponent(token)}`);
  }
  markPurchased(token: string, itemId: string, body: { name?: string; quantity: number }) {
    return this.post<SharedItem>(
      `/shared/${encodeURIComponent(token)}/items/${encodeURIComponent(itemId)}/purchases`,
      body,
    );
  }
  revertPurchase(token: string, purchaseId: string, body: { name?: string }) {
    return this.post<SharedItem>(
      `/shared/${encodeURIComponent(token)}/purchases/${encodeURIComponent(purchaseId)}/revert`,
      body,
    );
  }
}
