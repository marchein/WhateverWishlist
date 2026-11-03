import { Router } from 'express';
import { imageCache } from '../services/image-cache.js';
import { notFound } from '../errors.js';

export function imageCacheRouter(): Router {
  const router = Router();

  router.get('/:hash', async (req, res) => {
    const { hash } = req.params;

    if (!/^[a-f0-9]{16}$/.test(hash)) {
      throw notFound('Image');
    }

    const buffer = await imageCache.getImage(hash);
    if (!buffer) {
      throw notFound('Image');
    }

    res.set({
      'Content-Type': 'image/jpeg',
      'Cache-Control': 'public, max-age=31536000, immutable',
      'Content-Length': buffer.length,
    });
    res.send(buffer);
  });

  return router;
}
