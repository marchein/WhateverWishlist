import bcrypt from 'bcryptjs';
import type { DB } from './db.js';
import { passwordSchema, registerSchema } from './validation.js';
import { imageCache } from './services/image-cache.js';
import type { ItemRow } from './models.js';

export interface AdminUser {
  id: string;
  email: string;
  displayName: string;
  createdAt: string;
  wishlists: {
    id: string;
    title: string;
    description: string | null;
    eventDate: string | null;
    itemCount: number;
    createdAt: string;
    updatedAt: string;
  }[];
}

export function listUsers(db: DB): AdminUser[] {
  const users = db.prepare(`
    SELECT id, email, display_name AS displayName, created_at AS createdAt
    FROM users ORDER BY email COLLATE NOCASE
  `).all() as Omit<AdminUser, 'wishlists'>[];
  const wishlists = db.prepare(`
    SELECT w.id, w.owner_id AS ownerId, w.title, w.description, w.event_date AS eventDate,
           w.created_at AS createdAt, w.updated_at AS updatedAt, COUNT(i.id) AS itemCount
    FROM wishlists w LEFT JOIN items i ON i.wishlist_id = w.id
    GROUP BY w.id ORDER BY w.created_at, w.id
  `).all() as (AdminUser['wishlists'][number] & { ownerId: string })[];
  const byOwner = new Map<string, AdminUser['wishlists']>();
  for (const { ownerId, ...wishlist } of wishlists) {
    const owned = byOwner.get(ownerId) ?? [];
    owned.push(wishlist);
    byOwner.set(ownerId, owned);
  }
  return users.map((user) => ({ ...user, wishlists: byOwner.get(user.id) ?? [] }));
}

export async function resetPassword(db: DB, email: string, password: string): Promise<string> {
  const normalizedEmail = registerSchema.shape.email.parse(email);
  passwordSchema.parse(password);
  const user = db.prepare('SELECT id, email FROM users WHERE email = ?').get(normalizedEmail) as
    { id: string; email: string } | undefined;
  if (!user) throw new Error('User not found');
  const hash = await bcrypt.hash(password, 12);
  const result = db.prepare(`
    UPDATE users SET password_hash = ?, session_version = session_version + 1 WHERE id = ?
  `).run(hash, user.id);
  if (result.changes !== 1) throw new Error('User no longer exists; password was not reset');
  return user.email;
}

export async function cacheAllImages(db: DB): Promise<{ cached: number; skipped: number; errors: number }> {
  const items = db.prepare('SELECT * FROM items WHERE image_url IS NOT NULL').all() as ItemRow[];
  
  let cached = 0;
  let skipped = 0;
  let errors = 0;

  for (const item of items) {
    if (!item.image_url) {
      skipped++;
      continue;
    }

    // Skip local uploads - they're already on our server
    if (item.image_url.startsWith('/uploads/') || item.image_url.startsWith('/_cache/')) {
      skipped++;
      continue;
    }

    try {
      const cachedUrl = await imageCache.cacheImage(item.image_url);
      
      // Only log and count, don't update the database - keep the original URL
      if (cachedUrl !== item.image_url) {
        cached++;
        console.log(`[Admin] Cached image for item ${item.id}: ${item.image_url} -> ${cachedUrl}`);
      } else {
        skipped++;
      }
    } catch (error) {
      errors++;
      console.error(`[Admin] Failed to cache image for item ${item.id}:`, error);
    }
  }

  return { cached, skipped, errors };
}
