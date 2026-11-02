import Database from 'better-sqlite3';
import { mkdirSync } from 'node:fs';
import path from 'node:path';

export type DB = Database.Database;

// Append new migrations to the end; never edit an already released one.
const migrations: string[] = [
  `
  CREATE TABLE users (
    id            TEXT PRIMARY KEY,
    email         TEXT NOT NULL UNIQUE COLLATE NOCASE,
    display_name  TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    created_at    TEXT NOT NULL
  );

  CREATE TABLE wishlists (
    id          TEXT PRIMARY KEY,
    owner_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title       TEXT NOT NULL,
    description TEXT,
    event_date  TEXT,
    share_token TEXT NOT NULL UNIQUE,
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL
  );
  CREATE INDEX idx_wishlists_owner ON wishlists(owner_id);

  CREATE TABLE items (
    id          TEXT PRIMARY KEY,
    wishlist_id TEXT NOT NULL REFERENCES wishlists(id) ON DELETE CASCADE,
    title       TEXT NOT NULL,
    notes       TEXT,
    image_url   TEXT,
    price       REAL,
    currency    TEXT,
    priority    INTEGER NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),
    quantity    INTEGER NOT NULL DEFAULT 1 CHECK (quantity >= 1),
    links       TEXT NOT NULL DEFAULT '[]',
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL
  );
  CREATE INDEX idx_items_wishlist ON items(wishlist_id);

  -- Purchases are never deleted: a reverted purchase keeps who/when so the history stays complete.
  CREATE TABLE purchases (
    id                  TEXT PRIMARY KEY,
    item_id             TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    quantity            INTEGER NOT NULL CHECK (quantity >= 1),
    buyer_name          TEXT NOT NULL,
    buyer_user_id       TEXT REFERENCES users(id) ON DELETE SET NULL,
    created_at          TEXT NOT NULL,
    reverted_at         TEXT,
    reverted_by_name    TEXT,
    reverted_by_user_id TEXT REFERENCES users(id) ON DELETE SET NULL
  );
  CREATE INDEX idx_purchases_item ON purchases(item_id);
  `,
  `ALTER TABLE users ADD COLUMN session_version INTEGER NOT NULL DEFAULT 0;`,
];

export function openDatabase(file: string): DB {
  if (file !== ':memory:') mkdirSync(path.dirname(file), { recursive: true });
  const db = new Database(file);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  migrate(db);
  return db;
}

function migrate(db: DB): void {
  const current = db.pragma('user_version', { simple: true }) as number;
  for (let version = current; version < migrations.length; version++) {
    db.transaction(() => {
      db.exec(migrations[version]!);
      db.pragma(`user_version = ${version + 1}`);
    })();
  }
}
