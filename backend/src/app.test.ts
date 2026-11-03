import assert from 'node:assert/strict';
import type { AddressInfo } from 'node:net';
import { after, before, describe, it } from 'node:test';
import { createApp } from './app.js';
import { openDatabase } from './db.js';
import { version } from './version.js';

const db = openDatabase(':memory:');
const server = createApp(db).listen(0);
let base = '';

async function api(path: string, options: { method?: string; body?: unknown; token?: string } = {}) {
  const response = await fetch(`${base}/api${path}`, {
    method: options.method ?? (options.body ? 'POST' : 'GET'),
    headers: {
      'content-type': 'application/json',
      ...(options.token ? { authorization: `Bearer ${options.token}` } : {}),
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
  });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : undefined };
}

describe('wishlist API', () => {
  let ownerToken = '';
  let friendToken = '';
  let wishlistId = '';
  let shareToken = '';
  let itemId = '';

  before(async () => {
    await new Promise<void>((resolve) => server.once('listening', resolve));
    base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;

    const owner = await api('/auth/register', {
      body: { email: 'Owner@Example.com', password: 'secret-password', displayName: 'Olivia' },
    });
    assert.equal(owner.status, 201);
    ownerToken = owner.body.token;

    const friend = await api('/auth/register', {
      body: { email: 'friend@example.com', password: 'secret-password', displayName: 'Fred' },
    });
    friendToken = friend.body.token;
  });

  after(() => {
    server.close();
    db.close();
  });

  it('reports the running backend version publicly without caching it', async () => {
    const response = await fetch(`${base}/api/health`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.deepEqual(await response.json(), { ok: true, version });
    assert.ok(version.length > 0);
  });

  it('rejects duplicate registrations and bad logins', async () => {
    const duplicate = await api('/auth/register', {
      body: { email: 'owner@example.com', password: 'secret-password', displayName: 'X' },
    });
    assert.equal(duplicate.status, 409);
    assert.equal(duplicate.body.code, 'EMAIL_TAKEN');
    const badLogin = await api('/auth/login', { body: { email: 'owner@example.com', password: 'wrong-password' } });
    assert.equal(badLogin.status, 401);
    assert.equal(badLogin.body.code, 'INVALID_CREDENTIALS');
    const login = await api('/auth/login', { body: { email: 'OWNER@example.com', password: 'secret-password' } });
    assert.equal(login.status, 200);
  });

  it('lets the owner create a wishlist with items', async () => {
    const wishlist = await api('/wishlists', { token: ownerToken, body: { title: 'Christmas' } });
    assert.equal(wishlist.status, 201);
    wishlistId = wishlist.body.id;
    shareToken = wishlist.body.shareToken;

    const item = await api(`/wishlists/${wishlistId}/items`, {
      token: ownerToken,
      body: { title: 'Lego set', price: 49.999, currency: 'eur', quantity: 2, priority: 5, links: ['https://shop.example/lego'] },
    });
    assert.equal(item.status, 201);
    assert.equal(item.body.price, 50);
    assert.equal(item.body.currency, 'EUR');
    itemId = item.body.id;

    const invalid = await api(`/wishlists/${wishlistId}/items`, {
      token: ownerToken,
      body: { title: 'Bad', links: ['javascript:alert(1)'] },
    });
    assert.equal(invalid.status, 400);
    assert.equal(invalid.body.code, 'VALIDATION_FAILED');
  });

  it('keeps wishlists private to their owner', async () => {
    const asFriend = await api(`/wishlists/${wishlistId}`, { token: friendToken });
    assert.equal(asFriend.status, 404);
    assert.equal(asFriend.body.code, 'WISHLIST_NOT_FOUND');
    const anonymous = await api(`/wishlists/${wishlistId}`);
    assert.equal(anonymous.status, 401);
    assert.equal(anonymous.body.code, 'AUTH_REQUIRED');
    const edit = await api(`/wishlists/${wishlistId}`, {
      method: 'PATCH', token: friendToken, body: { title: 'Unauthorized edit' },
    });
    assert.equal(edit.status, 404);
    const add = await api(`/wishlists/${wishlistId}/items`, {
      token: friendToken, body: { title: 'Unauthorized item' },
    });
    assert.equal(add.status, 404);
    const shared = await api(`/shared/${shareToken}`, { token: friendToken });
    assert.equal(shared.status, 200);
    assert.equal(shared.body.isOwner, false);
  });

  it('PATCH only touches the provided fields', async () => {
    const updated = await api(`/wishlists/${wishlistId}/items/${itemId}`, {
      method: 'PATCH',
      token: ownerToken,
      body: { notes: 'Any colour' },
    });
    assert.equal(updated.status, 200);
    assert.equal(updated.body.notes, 'Any colour');
    assert.equal(updated.body.priority, 5);
    assert.equal(updated.body.quantity, 2);
    assert.equal(updated.body.price, 50);
  });

  it('preserves existing share tokens through owner views, edits and version checks', async () => {
    await api('/health');
    await api(`/wishlists/${wishlistId}`, { token: ownerToken });
    const edited = await api(`/wishlists/${wishlistId}`, {
      method: 'PATCH', token: ownerToken, body: { title: 'Christmas' },
    });
    assert.equal(edited.body.shareToken, shareToken);
    const shared = await api(`/shared/${shareToken}`);
    assert.equal(shared.status, 200);
    assert.equal(shared.body.wishlist.id, wishlistId);
    assert.equal(shared.body.wishlist.title, 'Christmas');
  });

  it('lets guests and users mark items as bought and undo it, with full history', async () => {
    const noName = await api(`/shared/${shareToken}/items/${itemId}/purchases`, { body: {} });
    assert.equal(noName.status, 400);
    assert.equal(noName.body.code, 'NAME_REQUIRED');

    const guest = await api(`/shared/${shareToken}/items/${itemId}/purchases`, { body: { name: 'Grandma' } });
    assert.equal(guest.status, 201);
    assert.equal(guest.body.purchasedQuantity, 1);

    const fred = await api(`/shared/${shareToken}/items/${itemId}/purchases`, { token: friendToken, body: {} });
    assert.equal(fred.status, 201);
    assert.equal(fred.body.purchasedQuantity, 2);
    assert.equal(fred.body.purchases[1].buyerName, 'Fred');
    assert.equal(fred.body.purchases[1].isMine, true);

    const tooMany = await api(`/shared/${shareToken}/items/${itemId}/purchases`, { body: { name: 'Uncle' } });
    assert.equal(tooMany.status, 409);
    assert.equal(tooMany.body.code, 'ALREADY_BOUGHT');

    const grandmaPurchase = guest.body.purchases[0].id;
    const reverted = await api(`/shared/${shareToken}/purchases/${grandmaPurchase}/revert`, { body: { name: 'Uncle' } });
    assert.equal(reverted.status, 200);
    assert.equal(reverted.body.purchasedQuantity, 1);
    assert.equal(reverted.body.purchases.length, 2);
    assert.equal(reverted.body.purchases[0].revertedByName, 'Uncle');

    const again = await api(`/shared/${shareToken}/purchases/${grandmaPurchase}/revert`, { body: { name: 'Uncle' } });
    assert.equal(again.status, 409);
    assert.equal(again.body.code, 'ALREADY_UNDONE');

    const greedy = await api(`/shared/${shareToken}/items/${itemId}/purchases`, { body: { name: 'Uncle', quantity: 2 } });
    assert.equal(greedy.status, 409);
    assert.equal(greedy.body.code, 'NOT_ENOUGH_REMAINING');
    assert.deepEqual(greedy.body.params, { remaining: 1 });

    const view = await api(`/shared/${shareToken}`);
    assert.equal(view.body.isOwner, false);
    assert.equal(view.body.wishlist.ownerName, 'Olivia');
    assert.equal(view.body.items[0].purchases.length, 2);
  });

  it('never shows purchases to the owner', async () => {
    const shared = await api(`/shared/${shareToken}`, { token: ownerToken });
    assert.equal(shared.body.isOwner, true);
    assert.equal(shared.body.items[0].purchases, undefined);
    assert.equal(shared.body.items[0].purchasedQuantity, undefined);

    const own = await api(`/wishlists/${wishlistId}`, { token: ownerToken });
    assert.equal(own.body.items[0].purchases, undefined);

    const markOwn = await api(`/shared/${shareToken}/items/${itemId}/purchases`, { token: ownerToken, body: {} });
    assert.equal(markOwn.status, 403);
    assert.equal(markOwn.body.code, 'OWN_WISHLIST');
  });

  it('renders escaped link preview tags without purchase data', async () => {
    await api(`/wishlists/${wishlistId}`, { method: 'PATCH', token: ownerToken, body: { title: 'Christmas <2026>' } });
    await api(`/wishlists/${wishlistId}/items`, {
      token: ownerToken,
      body: { title: 'Book', priority: 5, imageUrl: '/uploads/123e4567-e89b-12d3-a456-426614174000.png' },
    });

    const german = await fetch(`${base}/api/shared/${shareToken}/preview`);
    assert.match(german.headers.get('content-type') ?? '', /text\/html/);
    const html = await german.text();
    assert.match(html, /<meta property="og:title" content="Christmas &lt;2026&gt; – Wunschliste von Olivia">/);
    assert.match(html, /<meta property="og:description" content="2 Wünsche">/);
    assert.match(html, /<meta property="og:image" content="http:\/\/127\.0\.0\.1:\d+\/uploads\/123e4567-[^"]+\.png">/);
    assert.match(html, /<meta name="robots" content="noindex, nofollow">/);
    assert.doesNotMatch(html, /Grandma|Fred|bought|gekauft/i);

    const english = await fetch(`${base}/api/shared/${shareToken}/preview`, {
      headers: { 'accept-language': 'en-GB,en;q=0.9' },
    });
    assert.match(await english.text(), /Olivia&#39;s wishlist/);

    const missing = await fetch(`${base}/api/shared/does-not-exist/preview`);
    assert.equal(missing.status, 200);
    assert.match(await missing.text(), /Wunschliste nicht gefunden/);
  });

  it('lets logged-in recipients follow a shared list and unfollow it again', async () => {
    const anonymous = await api(`/shared/${shareToken}/follow`, { method: 'PUT' });
    assert.equal(anonymous.status, 401);
    assert.equal(anonymous.body.code, 'AUTH_REQUIRED');

    const own = await api(`/shared/${shareToken}/follow`, { method: 'PUT', token: ownerToken });
    assert.equal(own.status, 403);
    assert.equal(own.body.code, 'OWN_WISHLIST');

    assert.equal((await api(`/shared/${shareToken}`, { token: friendToken })).body.isFollowing, false);
    for (let i = 0; i < 2; i++) {
      const followed = await api(`/shared/${shareToken}/follow`, { method: 'PUT', token: friendToken });
      assert.equal(followed.status, 200);
      assert.equal(followed.body.isFollowing, true);
    }
    assert.equal((await api(`/shared/${shareToken}`, { token: friendToken })).body.isFollowing, true);

    const list = await api('/wishlists/followed', { token: friendToken });
    assert.equal(list.status, 200);
    assert.equal(list.body.length, 1);
    assert.equal(list.body[0].id, wishlistId);
    assert.equal(list.body[0].shareToken, shareToken);
    assert.equal(list.body[0].ownerName, 'Olivia');
    assert.equal(list.body[0].itemCount, 2);
    assert.deepEqual((await api('/wishlists/followed', { token: ownerToken })).body, []);
    assert.equal((await api('/wishlists', { token: friendToken })).body.length, 0);

    const unfollowed = await api(`/shared/${shareToken}/follow`, { method: 'DELETE', token: friendToken });
    assert.equal(unfollowed.body.isFollowing, false);
    assert.deepEqual((await api('/wishlists/followed', { token: friendToken })).body, []);

    await api(`/shared/${shareToken}/follow`, { method: 'PUT', token: friendToken });
  });

  it('lets the owner see and remove followers, but nobody else', async () => {
    const followers = await api(`/wishlists/${wishlistId}/followers`, { token: ownerToken });
    assert.equal(followers.status, 200);
    assert.equal(followers.body.length, 1);
    assert.equal(followers.body[0].displayName, 'Fred');
    assert.equal(followers.body[0].email, undefined);
    assert.equal((await api(`/wishlists/${wishlistId}`, { token: ownerToken })).body.followerCount, 1);

    const fredId = followers.body[0].userId;
    assert.equal((await api(`/wishlists/${wishlistId}/followers`, { token: friendToken })).status, 404);
    const foreignRemoval = await api(`/wishlists/${wishlistId}/followers/${fredId}`, {
      method: 'DELETE', token: friendToken,
    });
    assert.equal(foreignRemoval.status, 404);

    const removed = await api(`/wishlists/${wishlistId}/followers/${fredId}`, { method: 'DELETE', token: ownerToken });
    assert.equal(removed.status, 204);
    assert.deepEqual((await api('/wishlists/followed', { token: friendToken })).body, []);
    const again = await api(`/wishlists/${wishlistId}/followers/${fredId}`, { method: 'DELETE', token: ownerToken });
    assert.equal(again.status, 404);
    assert.equal(again.body.code, 'FOLLOWER_NOT_FOUND');

    await api(`/shared/${shareToken}/follow`, { method: 'PUT', token: friendToken });
  });

  it('can keep followers on the new link when the share token is regenerated', async () => {
    const regenerated = await api(`/wishlists/${wishlistId}/share-token`, {
      token: ownerToken, body: { keepFollowers: true },
    });
    assert.notEqual(regenerated.body.shareToken, shareToken);
    assert.equal((await api(`/shared/${shareToken}`)).status, 404);
    const followed = await api('/wishlists/followed', { token: friendToken });
    assert.equal(followed.body.length, 1);
    assert.equal(followed.body[0].shareToken, regenerated.body.shareToken);
    shareToken = regenerated.body.shareToken;
  });

  it('invalidates the old link and removes followers by default when the share token is regenerated', async () => {
    assert.equal((await api('/wishlists/followed', { token: friendToken })).body.length, 1);
    const regenerated = await api(`/wishlists/${wishlistId}/share-token`, { method: 'POST', token: ownerToken });
    assert.notEqual(regenerated.body.shareToken, shareToken);
    assert.equal((await api(`/shared/${shareToken}`)).status, 404);
    assert.equal((await api(`/shared/${regenerated.body.shareToken}`)).status, 200);
    assert.deepEqual((await api('/wishlists/followed', { token: friendToken })).body, []);
    assert.equal((await api(`/wishlists/${wishlistId}`, { token: ownerToken })).body.followerCount, 0);
  });

  it('refuses to scrape internal addresses', async () => {
    const result = await api('/scrape', {
      token: ownerToken,
      body: { input: 'http://169.254.169.254/latest/meta-data/' },
    });
    assert.equal(result.status, 200);
    assert.equal(result.body.status, 'failed');
    assert.equal(result.body.messages[0].code, 'PRIVATE_ADDRESS');
  });
});
