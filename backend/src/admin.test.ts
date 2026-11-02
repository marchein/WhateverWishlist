import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import type { AddressInfo } from 'node:net';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, beforeEach, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { createApp } from './app.js';
import { listUsers, resetPassword } from './admin.js';
import { signToken } from './auth.js';
import { config } from './config.js';
import { openDatabase, type DB } from './db.js';
import type { UserRow } from './models.js';

const originalPassword = 'original-test-password';
const originalHash = bcrypt.hashSync(originalPassword, 12);
const originalToken = signToken('owner-a');
const legacyToken = jwt.sign({}, config.jwtSecret, { subject: 'owner-a', algorithm: 'HS256' });

describe('administration CLI', () => {
  let directory: string;
  let databaseFile: string;
  let db: DB;

  beforeEach(() => {
    directory = mkdtempSync(path.join(tmpdir(), 'wishlist-admin-'));
    databaseFile = path.join(directory, 'wishlist.db');
    db = openDatabase(databaseFile);
    const insertUser = db.prepare(`
      INSERT INTO users (id, email, display_name, password_hash, created_at)
      VALUES (?, ?, ?, ?, '2026-01-01T00:00:00.000Z')
    `);
    insertUser.run('owner-a', 'alice@example.com', 'Alice', originalHash);
    insertUser.run('owner-b', 'bob@example.com', 'Bob', originalHash);
    insertUser.run('owner-c', 'carol@example.com', 'Carol', originalHash);
    const insertWishlist = db.prepare(`
      INSERT INTO wishlists (id, owner_id, title, share_token, created_at, updated_at)
      VALUES (?, ?, ?, ?, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')
    `);
    insertWishlist.run('list-a', 'owner-a', 'Birthday', 'existing-share-token');
    insertWishlist.run('list-b', 'owner-a', 'Christmas', 'second-share-token');
    insertWishlist.run('list-c', 'owner-b', 'Books', 'third-share-token');
    db.prepare(`
      INSERT INTO items (id, wishlist_id, title, created_at, updated_at)
      VALUES ('item-a', 'list-a', 'A book', '2026-01-01', '2026-01-01')
    `).run();
  });

  afterEach(() => {
    if (db.open) db.close();
    rmSync(directory, { recursive: true });
  });

  const cli = (args: string[], input?: string, file?: string) => spawnSync(process.execPath, [
    '--import', 'tsx', fileURLToPath(new URL('./admin-cli.ts', import.meta.url)), ...args,
  ], {
    env: { ...process.env, DATABASE_FILE: file ?? databaseFile },
    encoding: 'utf8',
    input,
    timeout: 15_000,
  });

  it('lists every user with all and only their own wishlists, including empty accounts', () => {
    const result = cli(['users']);
    assert.equal(result.status, 0, result.stderr);
    const { users } = JSON.parse(result.stdout) as { users: ReturnType<typeof listUsers> };
    assert.deepEqual(users.map((user) => user.email), ['alice@example.com', 'bob@example.com', 'carol@example.com']);
    assert.deepEqual(users[0].wishlists.map((wishlist) => wishlist.id), ['list-a', 'list-b']);
    assert.equal(users[0].wishlists[0].itemCount, 1);
    assert.deepEqual(users[1].wishlists.map((wishlist) => wishlist.id), ['list-c']);
    assert.deepEqual(users[2].wishlists, []);
    assert.doesNotMatch(result.stdout, /password|hash|session|share_token|shareToken|existing-share-token/i);
    assert.equal(result.stderr, '');
  });

  it('returns an empty JSON array for an empty database', () => {
    db.prepare('DELETE FROM users').run();
    const result = cli(['users']);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout), { users: [] });
  });

  it('resets through stdin, revokes old sessions, preserves other users and existing share links', async () => {
    const server = createApp(db).listen(0);
    await new Promise<void>((resolve) => server.once('listening', resolve));
    const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}/api`;
    const me = (token: string) => fetch(`${base}/auth/me`, { headers: { authorization: `Bearer ${token}` } });
    const login = (password: string) => fetch(`${base}/auth/login`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email: 'alice@example.com', password }),
    });
    try {
      assert.equal((await me(originalToken)).status, 200);
      assert.equal((await me(legacyToken)).status, 200);
      const newPassword = 'new-test-password';
      const result = cli(['reset-password', 'ALICE@EXAMPLE.COM', '--stdin'], `${newPassword}\n`);
      assert.equal(result.status, 0, result.stderr);
      assert.match(result.stdout, /All login sessions revoked/);
      assert.doesNotMatch(result.stdout + result.stderr, new RegExp(newPassword));
      const alice = db.prepare('SELECT * FROM users WHERE id = ?').get('owner-a') as UserRow;
      assert.notEqual(alice.password_hash, newPassword);
      assert.equal(await bcrypt.compare(newPassword, alice.password_hash), true);
      assert.equal(alice.session_version, 1);
      const bob = db.prepare('SELECT * FROM users WHERE id = ?').get('owner-b') as UserRow;
      assert.equal(bob.password_hash, originalHash);
      assert.equal(bob.session_version, 0);
      assert.equal((await me(originalToken)).status, 401);
      assert.equal((await me(legacyToken)).status, 401);
      assert.equal((await me(signToken('owner-b'))).status, 200);
      assert.equal((await login(originalPassword)).status, 401);
      const loggedIn = await login(newPassword);
      assert.equal(loggedIn.status, 200);
      const { token } = await loggedIn.json() as { token: string };
      assert.equal((await me(token)).status, 200);
      const guest = await fetch(`${base}/shared/existing-share-token`);
      assert.equal(guest.status, 200);
      const revokedOwner = await fetch(`${base}/shared/existing-share-token`, {
        headers: { authorization: `Bearer ${originalToken}` },
      });
      assert.equal(revokedOwner.status, 401, 'a stale owner session must not silently become a guest and reveal purchases');
      const ownerView = await fetch(`${base}/shared/existing-share-token`, {
        headers: { authorization: `Bearer ${token}` },
      });
      const shared = await ownerView.json() as { isOwner: boolean; items: Record<string, unknown>[] };
      assert.equal(shared.isOwner, true);
      assert.equal(shared.items[0]['purchases'], undefined);
      assert.equal(shared.items[0]['purchasedQuantity'], undefined);
    } finally {
      await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    }
  });

  for (const [label, input] of [
    ['short passwords', 'short\n'],
    ['passwords exceeding 72 UTF-8 bytes', `${'\u00e4'.repeat(37)}\n`],
    ['multiple lines', 'valid-password\nanother-password\n'],
    ['empty input', ''],
  ]) {
    it(`rejects ${label} without changing a password or session version`, () => {
      const result = cli(['reset-password', 'alice@example.com', '--stdin'], input);
      assert.equal(result.status, 1);
      assert.match(result.stderr, /Error:/);
      assert.equal(result.stdout, '');
      const alice = db.prepare('SELECT * FROM users WHERE id = ?').get('owner-a') as UserRow;
      assert.equal(alice.password_hash, originalHash);
      assert.equal(alice.session_version, 0);
    });
  }

  it('rejects unknown users without creating an account', () => {
    const result = cli(['reset-password', 'unknown@example.com', '--stdin'], 'valid-test-password\n');
    assert.equal(result.status, 1);
    assert.match(result.stderr, /User not found/);
    assert.equal(listUsers(db).length, 3);
  });

  it('requires explicit stdin mode instead of hanging without a terminal', () => {
    const result = cli(['reset-password', 'alice@example.com'], 'valid-test-password\n');
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Use --stdin/);
  });

  it('rejects plaintext command-line passwords without echoing them', () => {
    const password = 'do-not-echo-this-password';
    const result = cli(['reset-password', 'alice@example.com', '--password', password]);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Unknown command or arguments/);
    assert.doesNotMatch(result.stdout + result.stderr, new RegExp(password));
  });

  it('prints help and refuses to create a missing database', () => {
    const missing = path.join(directory, 'missing', 'wishlist.db');
    const help = cli(['--help'], undefined, missing);
    assert.equal(help.status, 0);
    assert.match(help.stdout, /reset-password/);
    const result = cli(['users'], undefined, missing);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Database does not exist/);
    assert.equal(existsSync(missing), false);
  });

  it('upgrades an existing database without changing its users, passwords or share tokens', () => {
    db.exec('ALTER TABLE users DROP COLUMN session_version; PRAGMA user_version = 1;');
    db.close();
    db = openDatabase(databaseFile);
    const alice = db.prepare('SELECT * FROM users WHERE id = ?').get('owner-a') as UserRow;
    assert.equal(alice.session_version, 0);
    assert.equal(alice.password_hash, originalHash);
    assert.equal(listUsers(db).length, 3);
    const row = db.prepare('SELECT share_token FROM wishlists WHERE id = ?').get('list-a') as { share_token: string };
    assert.equal(row.share_token, 'existing-share-token');
  });

  it('validates passwords and emails in the shared reset implementation as well', async () => {
    await assert.rejects(resetPassword(db, 'not-an-email', 'valid-password'));
    await assert.rejects(resetPassword(db, 'alice@example.com', 'short'));
    await resetPassword(db, ' Alice@Example.com ', 'valid-password-with-spaces ');
    const alice = db.prepare('SELECT * FROM users WHERE id = ?').get('owner-a') as UserRow;
    assert.equal(await bcrypt.compare('valid-password-with-spaces ', alice.password_hash), true);
  });
});
