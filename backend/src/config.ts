import { randomBytes } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

if (existsSync('.env')) {
  process.loadEnvFile('.env');
}

const env = process.env;
const isProduction = env.NODE_ENV === 'production';
const dataDir = path.dirname(env.DATABASE_FILE ?? 'data/wishlist.db');

function resolveJwtSecret(): string {
  if (env.JWT_SECRET) {
    if (env.JWT_SECRET.length < 32) throw new Error('JWT_SECRET must be at least 32 characters long');
    return env.JWT_SECRET;
  }
  if (isProduction) throw new Error('JWT_SECRET must be set in production');

  // Persist a generated dev secret so logins survive restarts of the watch process.
  const secretFile = path.join(dataDir, 'jwt-secret');
  if (existsSync(secretFile)) return readFileSync(secretFile, 'utf8').trim();
  mkdirSync(dataDir, { recursive: true });
  const secret = randomBytes(48).toString('base64url');
  writeFileSync(secretFile, secret, { mode: 0o600 });
  return secret;
}

function parseTrustProxy(value: string | undefined): boolean | number | string {
  if (!value) return false;
  if (value === 'true') return true;
  const asNumber = Number(value);
  return Number.isInteger(asNumber) ? asNumber : value;
}

export const config = {
  isProduction,
  port: Number(env.PORT ?? 3000),
  jwtSecret: resolveJwtSecret(),
  jwtExpiresIn: '30d',
  databaseFile: env.DATABASE_FILE ?? 'data/wishlist.db',
  uploadDir: env.UPLOAD_DIR ?? 'data/uploads',
  corsOrigins: (env.CORS_ORIGINS ?? 'http://localhost:4200,http://localhost:8100')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
  trustProxy: parseTrustProxy(env.TRUST_PROXY),
  /** Public origin used for absolute URLs in link previews; derived from the request when unset. */
  publicUrl: env.PUBLIC_URL?.trim().replace(/\/+$/, '') || undefined,
  scraperAcceptLanguage: env.SCRAPER_ACCEPT_LANGUAGE ?? 'de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7',
} as const;
