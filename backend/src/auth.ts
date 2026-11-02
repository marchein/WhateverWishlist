import type { RequestHandler } from 'express';
import jwt from 'jsonwebtoken';
import { config } from './config.js';
import type { DB } from './db.js';
import { HttpError } from './errors.js';

export interface AuthUser {
  id: string;
  email: string;
  displayName: string;
}

declare global {
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

export function signToken(userId: string, sessionVersion = 0): string {
  return jwt.sign({ sessionVersion }, config.jwtSecret, {
    subject: userId,
    algorithm: 'HS256',
    expiresIn: config.jwtExpiresIn,
  });
}

function userFromToken(db: DB, header: string | undefined): AuthUser | undefined {
  if (!header?.startsWith('Bearer ')) return undefined;
  let payload: jwt.JwtPayload | string;
  try {
    payload = jwt.verify(header.slice(7), config.jwtSecret, { algorithms: ['HS256'] });
  } catch (error) {
    if (error instanceof jwt.JsonWebTokenError) return undefined;
    throw error;
  }
  if (typeof payload === 'string' || typeof payload.sub !== 'string') return undefined;
  // Tokens issued before session revocation was introduced belong to the initial session version.
  const sessionVersion: unknown = payload.sessionVersion ?? 0;
  if (typeof sessionVersion !== 'number' || !Number.isSafeInteger(sessionVersion) || sessionVersion < 0) return undefined;
  const row = db
    .prepare('SELECT id, email, display_name, session_version FROM users WHERE id = ?')
    .get(payload.sub) as { id: string; email: string; display_name: string; session_version: number } | undefined;
  if (!row || row.session_version !== sessionVersion) return undefined;
  return { id: row.id, email: row.email, displayName: row.display_name };
}

/** Attaches req.user when a valid token is present, but lets anonymous requests through. */
export function optionalAuth(db: DB): RequestHandler {
  return (req, _res, next) => {
    req.user = userFromToken(db, req.headers.authorization);
    if (req.headers.authorization && !req.user) {
      throw new HttpError(401, 'AUTH_REQUIRED', 'Authentication required');
    }
    next();
  };
}

export function requireAuth(db: DB): RequestHandler {
  return (req, _res, next) => {
    req.user = userFromToken(db, req.headers.authorization);
    if (!req.user) throw new HttpError(401, 'AUTH_REQUIRED', 'Authentication required');
    next();
  };
}
