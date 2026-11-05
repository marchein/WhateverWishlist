import type { SharedItem } from '../../core/models';
import { sortItems } from './sort-items';

const item = (id: string, overrides: Partial<SharedItem>): SharedItem => ({
  id,
  wishlistId: 'w',
  title: id,
  notes: null,
  imageUrl: null,
  displayImageUrl: null,
  price: null,
  currency: 'EUR',
  priority: 3,
  quantity: 1,
  links: [],
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
  purchasedQuantity: 0,
  ...overrides,
});

const ids = (items: SharedItem[]) => items.map((i) => i.id);

describe('sortItems', () => {
  const old = item('old', { createdAt: '2026-01-01T00:00:00.000Z', price: 50, priority: 5 });
  const mid = item('mid', { createdAt: '2026-02-01T00:00:00.000Z', price: 10, priority: 1 });
  const fresh = item('fresh', { createdAt: '2026-03-01T00:00:00.000Z', priority: 3 });
  const boughtNew = item('boughtNew', { createdAt: '2026-04-01T00:00:00.000Z', purchasedQuantity: 1 });
  const partly = item('partly', { createdAt: '2026-01-15T00:00:00.000Z', quantity: 2, purchasedQuantity: 1 });
  const all = [old, boughtNew, mid, partly, fresh];

  it('shows the newest first and fully bought wishes last', () => {
    expect(ids(sortItems(all, 'newest', 'de-DE', true))).toEqual(['fresh', 'mid', 'partly', 'old', 'boughtNew']);
  });

  it('keeps the plain order when bought items should not sink (owner view)', () => {
    expect(ids(sortItems(all, 'newest', 'de-DE', false))[0]).toBe('boughtNew');
  });

  it('sorts by price with missing prices last in both directions', () => {
    expect(ids(sortItems([old, mid, fresh], 'priceAsc', 'de-DE', true))).toEqual(['mid', 'old', 'fresh']);
    expect(ids(sortItems([old, mid, fresh], 'priceDesc', 'de-DE', true))).toEqual(['old', 'mid', 'fresh']);
  });

  it('sorts by priority, then newest', () => {
    expect(ids(sortItems([old, mid, fresh], 'priority', 'de-DE', true))).toEqual(['old', 'fresh', 'mid']);
  });

  it('does not mutate the input', () => {
    const input = [old, mid];
    sortItems(input, 'newest', 'de-DE', true);
    expect(ids(input)).toEqual(['old', 'mid']);
  });
});
