import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toItemDto, type ItemRow } from './models.js';

const baseRow: ItemRow = {
  id: 'item-1',
  wishlist_id: 'list-1',
  title: 'Book',
  notes: null,
  image_url: 'https://shop.example/book.jpg',
  price: null,
  currency: null,
  priority: 3,
  quantity: 1,
  links: '[]',
  created_at: '2026-01-01T00:00:00.000Z',
  updated_at: '2026-01-01T00:00:00.000Z',
};

test('toItemDto keeps the original URL and exposes the cached copy as displayImageUrl', async () => {
  const dto = await toItemDto(baseRow, {
    getCachedImageUrl: async () => '/_cache/abc123',
    cacheImage: async () => '/_cache/abc123',
  });

  assert.equal(dto.imageUrl, 'https://shop.example/book.jpg');
  assert.equal(dto.displayImageUrl, '/_cache/abc123');
});

test('toItemDto falls back to the original URL and starts caching when not cached yet', async () => {
  const cached: string[] = [];
  const dto = await toItemDto(baseRow, {
    getCachedImageUrl: async () => null,
    cacheImage: async (url) => {
      cached.push(url);
      return url;
    },
  });

  assert.equal(dto.imageUrl, 'https://shop.example/book.jpg');
  assert.equal(dto.displayImageUrl, 'https://shop.example/book.jpg');
  assert.deepEqual(cached, ['https://shop.example/book.jpg']);
});

test('toItemDto leaves uploads and empty images untouched', async () => {
  const lookups: string[] = [];
  const imageCache = {
    getCachedImageUrl: async (url: string) => {
      lookups.push(url);
      return null;
    },
    cacheImage: async (url: string) => url,
  };

  const upload = await toItemDto({ ...baseRow, image_url: '/uploads/photo.png' }, imageCache);
  const none = await toItemDto({ ...baseRow, image_url: null }, imageCache);

  assert.equal(upload.displayImageUrl, '/uploads/photo.png');
  assert.equal(none.imageUrl, null);
  assert.equal(none.displayImageUrl, null);
  assert.deepEqual(lookups, []);
});
