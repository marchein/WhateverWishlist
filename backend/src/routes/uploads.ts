import { randomUUID } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import { Router } from 'express';
import multer from 'multer';
import { requireAuth } from '../auth.js';
import { config } from '../config.js';
import type { DB } from '../db.js';
import { HttpError } from '../errors.js';

/** Detects the real image type from magic bytes – the client supplied mimetype can't be trusted. */
function detectImageType(buffer: Buffer): 'jpg' | 'png' | 'gif' | 'webp' | undefined {
  if (buffer.subarray(0, 3).equals(Buffer.from([0xff, 0xd8, 0xff]))) return 'jpg';
  if (buffer.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'png';
  const header = buffer.subarray(0, 12).toString('latin1');
  if (header.startsWith('GIF87a') || header.startsWith('GIF89a')) return 'gif';
  if (header.startsWith('RIFF') && header.slice(8, 12) === 'WEBP') return 'webp';
  return undefined;
}

export function uploadsRouter(db: DB): Router {
  const router = Router();
  mkdirSync(config.uploadDir, { recursive: true });
  const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 5 * 1024 * 1024, files: 1 } });

  router.post('/', requireAuth(db), upload.single('image'), async (req, res) => {
    if (!req.file) throw new HttpError(400, 'NO_FILE', 'No image uploaded (expected form field "image")');
    const type = detectImageType(req.file.buffer);
    if (!type) throw new HttpError(400, 'UNSUPPORTED_IMAGE', 'Only JPEG, PNG, GIF and WebP images are supported');

    const fileName = `${randomUUID()}.${type}`;
    await writeFile(path.join(config.uploadDir, fileName), req.file.buffer);
    // Relative on purpose: clients resolve it against their API base URL (e.g. the dev server on another port).
    res.status(201).json({ url: `/uploads/${fileName}` });
  });

  return router;
}
