import { randomUUID } from 'node:crypto';
import { Router, type Request } from 'express';
import { optionalAuth } from '../auth.js';
import { config } from '../config.js';
import type { DB } from '../db.js';
import { HttpError, notFound } from '../errors.js';
import {
  activePurchasedQuantity,
  now,
  toItemDto,
  toPurchaseDto,
  type ItemRow,
  type PurchaseRow,
  type WishlistRow,
} from '../models.js';
import { imageCache } from '../services/image-cache.js';
import { previewLanguage, renderPreviewTags } from '../preview.js';
import { purchaseSchema, revertSchema } from '../validation.js';

/**
 * Public access to a wishlist through its share token. Anyone with the link (registered or not)
 * can see what was bought and mark items – except the owner, who never sees purchase data.
 */
export function sharedRouter(db: DB): Router {
  const router = Router();
  router.use(optionalAuth(db));

  const getWishlist = (token: string | undefined) => {
    const row = db
      .prepare(
        `SELECT w.*, u.display_name AS owner_name
         FROM wishlists w JOIN users u ON u.id = w.owner_id WHERE w.share_token = ?`,
      )
      .get(token) as (WishlistRow & { owner_name: string }) | undefined;
    if (!row) throw notFound('Wishlist');
    return row;
  };

  const assertNotOwner = (req: Request, wishlist: WishlistRow) => {
    if (req.user?.id === wishlist.owner_id) {
      throw new HttpError(403, 'OWN_WISHLIST', 'This is your own wishlist – no peeking at what was bought!');
    }
  };

  const requireUser = (req: Request) => {
    if (!req.user) throw new HttpError(401, 'AUTH_REQUIRED', 'Authentication required');
    return req.user;
  };

  const actorName = (req: Request, name: string | undefined) => {
    const resolved = name || req.user?.displayName;
    if (!resolved) throw new HttpError(400, 'NAME_REQUIRED', 'Please tell us your name');
    return resolved;
  };

  const getItem = (wishlistId: string, itemId: string | undefined) => {
    const row = db.prepare('SELECT * FROM items WHERE id = ? AND wishlist_id = ?').get(itemId, wishlistId) as
      | ItemRow
      | undefined;
    if (!row) throw notFound('Item');
    return row;
  };

  const purchasesFor = (itemId: string) =>
    db.prepare('SELECT * FROM purchases WHERE item_id = ? ORDER BY created_at ASC').all(itemId) as PurchaseRow[];

  const toSharedItem = async (item: ItemRow, purchases: PurchaseRow[], viewerId: string | undefined) => ({
    ...(await toItemDto(item, imageCache)),
    purchasedQuantity: activePurchasedQuantity(purchases),
    purchases: purchases.map((p) => toPurchaseDto(p, viewerId)),
  });

  // HTML <meta> fragment that the web server injects into the app's index.html for /s/<token>.
  // Deliberately contains nothing about purchases: the owner may share the link themselves.
  router.get('/:token/preview', (req, res) => {
    const row = db
      .prepare(
        `SELECT w.title, w.description, w.event_date, u.display_name AS owner_name,
                (SELECT COUNT(*) FROM items i WHERE i.wishlist_id = w.id) AS item_count,
                (SELECT i.image_url FROM items i WHERE i.wishlist_id = w.id AND i.image_url IS NOT NULL
                 ORDER BY i.priority DESC, i.created_at DESC LIMIT 1) AS image_url
         FROM wishlists w JOIN users u ON u.id = w.owner_id WHERE w.share_token = ?`,
      )
      .get(req.params.token) as
      | {
          title: string;
          description: string | null;
          event_date: string | null;
          owner_name: string;
          item_count: number;
          image_url: string | null;
        }
      | undefined;

    const origin = config.publicUrl ?? `${req.protocol}://${req.get('host')}`;
    res
      .type('html')
      .set('Cache-Control', 'no-store')
      .send(
        renderPreviewTags({
          language: previewLanguage(req.get('accept-language')),
          origin,
          pageUrl: `${origin}/s/${encodeURIComponent(req.params.token)}`,
          wishlist: row && {
            title: row.title,
            description: row.description,
            eventDate: row.event_date,
            ownerName: row.owner_name,
            itemCount: row.item_count,
            imageUrl: row.image_url,
          },
        }),
      );
  });

  router.get('/:token', async (req, res) => {
    const wishlist = getWishlist(req.params.token);
    const isOwner = req.user?.id === wishlist.owner_id;
    const items = db
      .prepare('SELECT * FROM items WHERE wishlist_id = ? ORDER BY priority DESC, created_at ASC')
      .all(wishlist.id) as ItemRow[];

    const header = {
      id: wishlist.id,
      title: wishlist.title,
      description: wishlist.description,
      eventDate: wishlist.event_date,
      ownerName: wishlist.owner_name,
    };

    if (isOwner) {
      res.json({ wishlist: header, isOwner, isFollowing: false, items: await Promise.all(items.map(item => toItemDto(item, imageCache))) });
      return;
    }

    const isFollowing =
      !!req.user &&
      !!db
        .prepare('SELECT 1 FROM wishlist_follows WHERE user_id = ? AND wishlist_id = ?')
        .get(req.user.id, wishlist.id);

    const purchases = db
      .prepare(
        `SELECT p.* FROM purchases p JOIN items i ON i.id = p.item_id
         WHERE i.wishlist_id = ? ORDER BY p.created_at ASC`,
      )
      .all(wishlist.id) as PurchaseRow[];
    const byItem = Map.groupBy(purchases, (p) => p.item_id);

    res.json({
      wishlist: header,
      isOwner,
      isFollowing,
      items: await Promise.all(items.map((item) => toSharedItem(item, byItem.get(item.id) ?? [], req.user?.id))),
    });
  });

  // Logged-in recipients can keep a list they were sent; it then appears on their start page.
  router.put('/:token/follow', (req, res) => {
    const user = requireUser(req);
    const wishlist = getWishlist(req.params.token);
    if (user.id === wishlist.owner_id) {
      throw new HttpError(403, 'OWN_WISHLIST', 'You cannot follow your own wishlist');
    }
    db.prepare(
      'INSERT OR IGNORE INTO wishlist_follows (user_id, wishlist_id, created_at) VALUES (?, ?, ?)',
    ).run(user.id, wishlist.id, now());
    res.json({ isFollowing: true });
  });

  router.delete('/:token/follow', (req, res) => {
    const user = requireUser(req);
    const wishlist = getWishlist(req.params.token);
    db.prepare('DELETE FROM wishlist_follows WHERE user_id = ? AND wishlist_id = ?').run(user.id, wishlist.id);
    res.json({ isFollowing: false });
  });

  router.post('/:token/items/:itemId/purchases', async (req, res) => {
    const wishlist = getWishlist(req.params.token);
    assertNotOwner(req, wishlist);
    const item = getItem(wishlist.id, req.params.itemId);
    const input = purchaseSchema.parse(req.body ?? {});
    const name = actorName(req, input.name);

    // Check + insert atomically so two people can't claim the last remaining piece at once.
    db.transaction(() => {
      const remaining = item.quantity - activePurchasedQuantity(purchasesFor(item.id));
      if (remaining <= 0) throw new HttpError(409, 'ALREADY_BOUGHT', 'This item has already been bought');
      if (input.quantity > remaining) {
        throw new HttpError(409, 'NOT_ENOUGH_REMAINING', `Only ${remaining} still needed`, { remaining });
      }

      db.prepare(
        `INSERT INTO purchases (id, item_id, quantity, buyer_name, buyer_user_id, created_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
      ).run(randomUUID(), item.id, input.quantity, name, req.user?.id ?? null, now());
    }).immediate();

    res.status(201).json(await toSharedItem(item, purchasesFor(item.id), req.user?.id));
  });

  // Undo a purchase. The record stays (with who reset it) so mistakes or mischief remain visible.
  router.post('/:token/purchases/:purchaseId/revert', async (req, res) => {
    const wishlist = getWishlist(req.params.token);
    assertNotOwner(req, wishlist);
    const input = revertSchema.parse(req.body ?? {});
    const name = actorName(req, input.name);

    const purchase = db
      .prepare(
        `SELECT p.* FROM purchases p JOIN items i ON i.id = p.item_id
         WHERE p.id = ? AND i.wishlist_id = ?`,
      )
      .get(req.params.purchaseId, wishlist.id) as PurchaseRow | undefined;
    if (!purchase) throw notFound('Purchase');

    const result = db
      .prepare(
        `UPDATE purchases SET reverted_at = ?, reverted_by_name = ?, reverted_by_user_id = ?
         WHERE id = ? AND reverted_at IS NULL`,
      )
      .run(now(), name, req.user?.id ?? null, purchase.id);
    if (result.changes === 0) throw new HttpError(409, 'ALREADY_UNDONE', 'This purchase was already undone');

    const item = getItem(wishlist.id, purchase.item_id);
    res.json(await toSharedItem(item, purchasesFor(item.id), req.user?.id));
  });

  return router;
}
