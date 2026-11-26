/**
 * Ties the web app to the native iOS app:
 * - apple-app-site-association: share links open in the app (Universal Links), Handoff between
 *   Safari and the app, and logins saved in Safari are offered in the app (shared web credentials).
 * - Smart App Banner: Safari on iPhone/iPad suggests opening or installing the app.
 * Both stay off until the operator configures the app in .env.
 */
import { Router, type Request } from 'express';

export interface IosAppConfig {
  /** "<Team ID>.<bundle ID>" of each app build that may claim this domain. */
  appIds: readonly string[];
  /** Numeric App Store ID for the Smart App Banner. */
  appStoreId?: string;
}

const APP_ID_PATTERN = /^[A-Z0-9]{10}\.[A-Za-z0-9.-]+$/;
const SHARE_TOKEN_PATTERN = /^[A-Za-z0-9_-]{8,64}$/;

/** Web paths the app can show; everything else (login, legal pages, …) stays in the browser. */
export const APP_LINK_PATHS = ['/s/*', '/wishlists', '/status'] as const;

export function parseIosAppConfig(env: { IOS_APP_IDS?: string; IOS_APP_STORE_ID?: string }): IosAppConfig {
  const appIds = (env.IOS_APP_IDS ?? '')
    .split(',')
    .map((id) => id.trim())
    .filter(Boolean);
  for (const id of appIds) {
    if (!APP_ID_PATTERN.test(id)) {
      throw new Error(`IOS_APP_IDS: "${id}" must look like <TEAMID>.<bundle id>, e.g. ABCDE12345.com.example.wishlist`);
    }
  }
  const appStoreId = env.IOS_APP_STORE_ID?.trim() || undefined;
  if (appStoreId && !/^\d+$/.test(appStoreId)) {
    throw new Error('IOS_APP_STORE_ID must be the numeric App Store ID, e.g. 1234567890');
  }
  return { appIds, appStoreId };
}

export function appSiteAssociation(appIds: readonly string[]) {
  return {
    applinks: {
      details: [{ appIDs: appIds, components: APP_LINK_PATHS.map((path) => ({ '/': path })) }],
    },
    webcredentials: { apps: appIds },
  };
}

/** `<meta name="apple-itunes-app">`; share pages pass their URL so "Open" lands on that list. */
export function smartBannerTag(appStoreId: string | undefined, appArgument?: string): string {
  if (!appStoreId) return '';
  const argument = appArgument ? `, app-argument=${appArgument}` : '';
  return `<meta name="apple-itunes-app" content="app-id=${appStoreId}${argument}">`;
}

export function publicOrigin(req: Request, publicUrl: string | undefined): string {
  return publicUrl ?? `${req.protocol}://${req.get('host')}`;
}

/**
 * `GET /.well-known/apple-app-site-association` and `GET /api/app/banner[?token=…]`, the latter
 * included into index.html by nginx (SSI) because Safari only reads the banner tag on page load.
 */
export function appLinksRouter(ios: IosAppConfig, publicUrl: string | undefined): Router {
  const router = Router();

  router.get('/.well-known/apple-app-site-association', (_req, res) => {
    if (ios.appIds.length === 0) {
      res.status(404).type('text').send('Not found');
      return;
    }
    // Apple's CDN caches the file anyway; a short max-age keeps changes from lingering.
    res.set('Cache-Control', 'public, max-age=3600').json(appSiteAssociation(ios.appIds));
  });

  router.get('/api/app/banner', (req, res) => {
    const token = typeof req.query.token === 'string' ? req.query.token : undefined;
    const appArgument =
      token && SHARE_TOKEN_PATTERN.test(token) ? `${publicOrigin(req, publicUrl)}/s/${token}` : undefined;
    res.type('html').set('Cache-Control', 'no-store').send(smartBannerTag(ios.appStoreId, appArgument));
  });

  return router;
}
