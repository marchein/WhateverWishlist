import bcrypt from 'bcryptjs';
import type { DB } from './db.js';
import { passwordSchema, registerSchema } from './validation.js';

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
