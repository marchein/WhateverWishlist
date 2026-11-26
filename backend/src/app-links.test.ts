import assert from 'node:assert/strict';
import type { Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { after, describe, it } from 'node:test';
import express from 'express';
import { appLinksRouter, parseIosAppConfig, type IosAppConfig } from './app-links.js';

const servers: Server[] = [];

async function serve(ios: IosAppConfig, publicUrl?: string): Promise<string> {
  const app = express();
  app.use(appLinksRouter(ios, publicUrl));
  const server = app.listen(0);
  servers.push(server);
  await new Promise<void>((resolve) => server.once('listening', resolve));
  return `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
}

after(() => servers.forEach((server) => server.close()));

describe('iOS app links', () => {
  it('parses and validates the configuration', () => {
    assert.deepEqual(parseIosAppConfig({}), { appIds: [], appStoreId: undefined });
    assert.deepEqual(
      parseIosAppConfig({ IOS_APP_IDS: ' ABCDE12345.com.example.app , ABCDE12345.com.example.beta', IOS_APP_STORE_ID: '123' }),
      { appIds: ['ABCDE12345.com.example.app', 'ABCDE12345.com.example.beta'], appStoreId: '123' },
    );
    assert.throws(() => parseIosAppConfig({ IOS_APP_IDS: 'com.example.app' }), /IOS_APP_IDS/);
    assert.throws(() => parseIosAppConfig({ IOS_APP_STORE_ID: 'id123' }), /IOS_APP_STORE_ID/);
  });

  it('serves nothing while no app is configured', async () => {
    const base = await serve({ appIds: [] });
    assert.equal((await fetch(`${base}/.well-known/apple-app-site-association`)).status, 404);
    const banner = await fetch(`${base}/api/app/banner`);
    assert.equal(banner.status, 200);
    assert.equal(await banner.text(), '');
  });

  it('serves the apple-app-site-association file as JSON', async () => {
    const base = await serve({ appIds: ['ABCDE12345.com.example.app'] });
    const response = await fetch(`${base}/.well-known/apple-app-site-association`);
    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-type') ?? '', /application\/json/);
    assert.deepEqual(await response.json(), {
      applinks: {
        details: [
          {
            appIDs: ['ABCDE12345.com.example.app'],
            components: [{ '/': '/s/*' }, { '/': '/wishlists' }, { '/': '/status' }],
          },
        ],
      },
      webcredentials: { apps: ['ABCDE12345.com.example.app'] },
    });
  });

  it('renders the Smart App Banner, pointing share pages to their list', async () => {
    const base = await serve({ appIds: [], appStoreId: '6835103795' }, 'https://wishlist.example.com');
    assert.equal(
      await (await fetch(`${base}/api/app/banner`)).text(),
      '<meta name="apple-itunes-app" content="app-id=6835103795">',
    );
    assert.equal(
      await (await fetch(`${base}/api/app/banner?token=abcDEF12_-`)).text(),
      '<meta name="apple-itunes-app" content="app-id=6835103795, app-argument=https://wishlist.example.com/s/abcDEF12_-">',
    );
    // Anything that isn't a share token is dropped instead of ending up in the page.
    assert.equal(
      await (await fetch(`${base}/api/app/banner?token=${encodeURIComponent('x"><script>')}`)).text(),
      '<meta name="apple-itunes-app" content="app-id=6835103795">',
    );
  });
});
