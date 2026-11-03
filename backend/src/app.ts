import cors from 'cors';
import express from 'express';
import { rateLimit } from 'express-rate-limit';
import helmet from 'helmet';
import { config } from './config.js';
import type { DB } from './db.js';
import { errorHandler, notFound } from './errors.js';
import { authRouter } from './routes/auth.js';
import { scrapeRouter } from './routes/scrape.js';
import { sharedRouter } from './routes/shared.js';
import { uploadsRouter } from './routes/uploads.js';
import { wishlistsRouter } from './routes/wishlists.js';
import { version } from './version.js';

export function createApp(db: DB) {
  const app = express();
  app.set('trust proxy', config.trustProxy);
  app.disable('x-powered-by');

  // Images are loaded by the frontend from a different origin, so allow cross-origin embedding.
  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  app.use(cors({ origin: config.corsOrigins }));
  app.use(express.json({ limit: '100kb' }));

  const authLimiter = rateLimit({
    windowMs: 15 * 60_000,
    limit: 30,
    message: { code: 'RATE_LIMITED', message: 'Too many attempts, please try again later' },
  });
  // Shared links accept anonymous writes, so keep them on a leash.
  const sharedWriteLimiter = rateLimit({
    windowMs: 15 * 60_000,
    limit: 100,
    skip: (req) => req.method === 'GET',
    message: { code: 'RATE_LIMITED', message: 'Too many requests, please try again later' },
  });

  app.get('/api/health', (_req, res) => {
    res.set('Cache-Control', 'no-store').json({ ok: true, version });
  });
  app.use('/api/auth', authLimiter, authRouter(db));
  app.use('/api/wishlists', wishlistsRouter(db));
  app.use('/api/shared', sharedWriteLimiter, sharedRouter(db));
  app.use('/api/scrape', scrapeRouter(db));
  app.use('/api/uploads', uploadsRouter(db));
  app.use(
    '/uploads',
    express.static(config.uploadDir, { index: false, dotfiles: 'deny', immutable: true, maxAge: '30d' }),
  );

  app.use('/api', () => {
    throw notFound('Endpoint');
  });
  app.use(errorHandler);
  return app;
}
