import { randomBytes, randomUUID } from 'node:crypto';
import { Router, type Request } from 'express';
import { requireAuth } from '../auth.js';
import type { DB } from '../db.js';
import { notFound } from '../errors.js';
import { now, toFollowedWishlistDto, toItemDto, toItemDtoWithCache, toWishlistDto, type ItemRow, type WishlistRow } from '../models.js';
import { imageCache } from '../services/image-cache.js';
import {
  createItemSchema,
  createWishlistSchema,
  regenerateShareTokenSchema,
  updateItemSchema,
  updateWishlistSchema,
} from '../validation.js';

export const newShareToken = () => randomBytes(16).toString('base64url');

/** Builds "col = @key" assignments only for keys the client actually sent (PATCH semantics). */
function pickUpdates(req: Request, parsed: Record<string, unknown>, columns: Record<string, string>) {
  const sets: string[] = [];
  const params: Record<string, unknown> = {};
  for (const [key, column] of Object.entries(columns)) {
    if (!Object.hasOwn(req.body ?? {}, key)) continue;
    const value = parsed[key];
    sets.push(`${column} = @${key}`);
    params[key] = Array.isArray(value) ? JSON.stringify(value) : value;
  }
  return { sets, params };
}

export function wishlistsRouter(db: DB): Router {
  const router = Router();
  router.use(requireAuth(db));

  const getOwnedWishlist = (id: string | undefined, userId: string) => {
    const row = db.prepare('SELECT * FROM wishlists WHERE id = ? AND owner_id = ?').get(id, userId) as
      | WishlistRow
      | undefined;
    if (!row) throw notFound('Wishlist');
    return row;
  };

  const getItem = (wishlistId: string, itemId: string | undefined) => {
    const row = db.prepare('SELECT * FROM items WHERE id = ? AND wishlist_id = ?').get(itemId, wishlistId) as
      | ItemRow
      | undefined;
    if (!row) throw notFound('Item');
    return row;
  };

  const touchWishlist = (id: string) => db.prepare('UPDATE wishlists SET updated_at = ? WHERE id = ?').run(now(), id);

  const followersOf = (wishlistId: string) =>
    (
      db
        .prepare(
          `SELECT u.id, u.display_name, f.created_at FROM wishlist_follows f JOIN users u ON u.id = f.user_id
           WHERE f.wishlist_id = ? ORDER BY f.created_at ASC`,
        )
        .all(wishlistId) as { id: string; display_name: string; created_at: string }[]
    ).map((row) => ({ userId: row.id, displayName: row.display_name, followedAt: row.created_at }));

  router.get('/', (req, res) => {
    const rows = db
      .prepare(
        `SELECT w.*, (SELECT COUNT(*) FROM items i WHERE i.wishlist_id = w.id) AS item_count
         FROM wishlists w WHERE w.owner_id = ? ORDER BY w.updated_at DESC`,
      )
      .all(req.user!.id) as (WishlistRow & { item_count: number })[];
    res.json(rows.map(toWishlistDto));
  });

  // Lists of other people the user follows through their share link.
  router.get('/followed', (req, res) => {
    const rows = db
      .prepare(
        `SELECT w.*, u.display_name AS owner_name, f.created_at AS followed_at,
                (SELECT COUNT(*) FROM items i WHERE i.wishlist_id = w.id) AS item_count
         FROM wishlist_follows f
         JOIN wishlists w ON w.id = f.wishlist_id
         JOIN users u ON u.id = w.owner_id
         WHERE f.user_id = ? AND w.owner_id != f.user_id
         ORDER BY f.created_at DESC`,
      )
      .all(req.user!.id) as (WishlistRow & { item_count: number; owner_name: string; followed_at: string })[];
    res.json(rows.map(toFollowedWishlistDto));
  });

  router.post('/', (req, res) => {
    const input = createWishlistSchema.parse(req.body);
    const timestamp = now();
    const row: WishlistRow = {
      id: randomUUID(),
      owner_id: req.user!.id,
      title: input.title,
      description: input.description,
      event_date: input.eventDate,
      share_token: newShareToken(),
      created_at: timestamp,
      updated_at: timestamp,
    };
    db.prepare(
      `INSERT INTO wishlists (id, owner_id, title, description, event_date, share_token, created_at, updated_at)
       VALUES (@id, @owner_id, @title, @description, @event_date, @share_token, @created_at, @updated_at)`,
    ).run(row);
    res.status(201).json(toWishlistDto({ ...row, item_count: 0 }));
  });

  // Owner view: deliberately contains no purchase information so the surprise isn't spoiled.
  router.get('/:id', async (req, res) => {
    const wishlist = getOwnedWishlist(req.params.id, req.user!.id);
    const items = db
      .prepare('SELECT * FROM items WHERE wishlist_id = ? ORDER BY priority DESC, created_at ASC')
      .all(wishlist.id) as ItemRow[];
    res.json({
      ...toWishlistDto({ ...wishlist, item_count: items.length }),
      followerCount: followersOf(wishlist.id).length,
      items: items.map(item => toItemDto(item)),
    });
  });

  router.patch('/:id', (req, res) => {
    const wishlist = getOwnedWishlist(req.params.id, req.user!.id);
    const input = updateWishlistSchema.parse(req.body);
    const { sets, params } = pickUpdates(req, input, {
      title: 'title',
      description: 'description',
      eventDate: 'event_date',
    });
    if (sets.length) {
      db.prepare(`UPDATE wishlists SET ${sets.join(', ')}, updated_at = @updatedAt WHERE id = @id`).run({
        ...params,
        updatedAt: now(),
        id: wishlist.id,
      });
    }
    res.json(toWishlistDto(getOwnedWishlist(wishlist.id, req.user!.id)));
  });

  router.delete('/:id', (req, res) => {
    const wishlist = getOwnedWishlist(req.params.id, req.user!.id);
    db.prepare('DELETE FROM wishlists WHERE id = ?').run(wishlist.id);
    res.status(204).end();
  });

  // Invalidates the old share link, e.g. when it was sent to the wrong people. The owner decides whether
  // followers keep access (their start page then points to the new link) or are removed with the old link.
  router.post('/:id/share-token', (req, res) => {
    const wishlist = getOwnedWishlist(req.params.id, req.user!.id);
    const { keepFollowers } = regenerateShareTokenSchema.parse(req.body ?? {});
    db.transaction(() => {
      db.prepare('UPDATE wishlists SET share_token = ?, updated_at = ? WHERE id = ?').run(
        newShareToken(),
        now(),
        wishlist.id,
      );
      if (!keepFollowers) db.prepare('DELETE FROM wishlist_follows WHERE wishlist_id = ?').run(wishlist.id);
    })();
    res.json(toWishlistDto(getOwnedWishlist(wishlist.id, req.user!.id)));
  });

  // Only display names are revealed: the owner learns who saved the list, not their account details.
  router.get('/:id/followers', (req, res) => {
    const wishlist = getOwnedWishlist(req.params.id, req.user!.id);
    res.json(followersOf(wishlist.id));
  });

  router.delete('/:id/followers/:userId', (req, res) => {
    const wishlist = getOwnedWishlist(req.params.id, req.user!.id);
    const result = db
      .prepare('DELETE FROM wishlist_follows WHERE wishlist_id = ? AND user_id = ?')
      .run(wishlist.id, req.params.userId);
    if (result.changes === 0) throw notFound('Follower');
    res.status(204).end();
  });

  router.post('/:id/items', async (req, res) => {
    const wishlist = getOwnedWishlist(req.params.id, req.user!.id);
    const input = createItemSchema.parse(req.body);
    const timestamp = now();
    const row: ItemRow = {
      id: randomUUID(),
      wishlist_id: wishlist.id,
      title: input.title,
      notes: input.notes,
      image_url: input.imageUrl,
      price: input.price,
      currency: input.currency,
      priority: input.priority,
      quantity: input.quantity,
      links: JSON.stringify(input.links),
      created_at: timestamp,
      updated_at: timestamp,
    };
    db.prepare(
      `INSERT INTO items (id, wishlist_id, title, notes, image_url, price, currency, priority, quantity, links, created_at, updated_at)
       VALUES (@id, @wishlist_id, @title, @notes, @image_url, @price, @currency, @priority, @quantity, @links, @created_at, @updated_at)`,
    ).run(row);
    touchWishlist(wishlist.id);
    res.status(201).json(toItemDto(row));
  });

  router.patch('/:id/items/:itemId', async (req, res) => {
    const wishlist = getOwnedWishlist(req.params.id, req.user!.id);
    const item = getItem(wishlist.id, req.params.itemId);
    const input = updateItemSchema.parse(req.body);
    const { sets, params } = pickUpdates(req, input, {
      title: 'title',
      notes: 'notes',
      imageUrl: 'image_url',
      price: 'price',
      currency: 'currency',
      priority: 'priority',
      quantity: 'quantity',
      links: 'links',
    });
    if (sets.length) {
      db.prepare(`UPDATE items SET ${sets.join(', ')}, updated_at = @updatedAt WHERE id = @id`).run({
        ...params,
        updatedAt: now(),
        id: item.id,
      });
      touchWishlist(wishlist.id);
    }
    res.json(toItemDto(getItem(wishlist.id, item.id)));
  });

  router.delete('/:id/items/:itemId', (req, res) => {
    const wishlist = getOwnedWishlist(req.params.id, req.user!.id);
    const item = getItem(wishlist.id, req.params.itemId);
    db.prepare('DELETE FROM items WHERE id = ?').run(item.id);
    touchWishlist(wishlist.id);
    res.status(204).end();
  });

  return router;
}
