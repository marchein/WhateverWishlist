import { createReadStream, existsSync, mkdirSync, readdirSync, statSync, unlinkSync, readFileSync } from 'node:fs';
import { writeFile, readFile, unlink } from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fetch } from 'undici';
import sharp from 'sharp';
import { config } from '../config.js';

interface CacheEntry {
  url: string;
  contentHash: string;
  size: number;
  createdAt: number;
  lastAccessedAt: number;
}

const MANIFEST_FILE = 'manifest.json';

export class ImageCache {
  private cacheDir: string;
  private manifest: Map<string, CacheEntry> = new Map();
  private manifestPath: string;

  constructor() {
    this.cacheDir = config.imageCache.dir;
    this.manifestPath = path.join(this.cacheDir, MANIFEST_FILE);
    this.initialize();
  }

  private initialize(): void {
    mkdirSync(this.cacheDir, { recursive: true });
    this.loadManifest();
    this.cleanupExpired();
  }

  private loadManifest(): void {
    try {
      if (existsSync(this.manifestPath)) {
        const data = JSON.parse(readFileSync(this.manifestPath, 'utf8'));
        this.manifest = new Map(Object.entries(data) as [string, CacheEntry][]);
      }
    } catch (error) {
      console.error('[ImageCache] Failed to load manifest:', error);
      this.manifest.clear();
    }
  }

  private async saveManifest(): Promise<void> {
    const data = Object.fromEntries(this.manifest);
    try {
      await writeFile(this.manifestPath, JSON.stringify(data, null, 2), 'utf8');
    } catch (error) {
      console.error('[ImageCache] Failed to save manifest:', error);
    }
  }

  private generateHash(url: string): string {
    return createHash('sha256').update(url).digest('hex').substring(0, 16);
  }

  private cleanupExpired(): void {
    const now = Date.now();
    const maxAgeMs = config.imageCache.maxAge * 24 * 60 * 60 * 1000;
    let cleaned = 0;

    for (const [hash, entry] of this.manifest) {
      if (now - entry.lastAccessedAt > maxAgeMs) {
        const filePath = path.join(this.cacheDir, hash);
        try {
          if (existsSync(filePath)) {
            unlinkSync(filePath);
            cleaned++;
          }
          this.manifest.delete(hash);
        } catch (error) {
          console.error(`[ImageCache] Failed to delete expired image ${hash}:`, error);
        }
      }
    }

    if (cleaned > 0) {
      console.log(`[ImageCache] Cleaned up ${cleaned} expired images (older than ${config.imageCache.maxAge} days)`);
      this.saveManifest().catch((e) => console.error('[ImageCache] Failed to save manifest after cleanup:', e));
    }
  }

  private getTotalSize(): number {
    let total = 0;
    for (const entry of this.manifest.values()) {
      total += entry.size;
    }
    return total;
  }

  private async enforceMaxSize(): Promise<void> {
    const currentSize = this.getTotalSize();
    if (currentSize <= config.imageCache.maxSize) return;

    console.log(
      `[ImageCache] Cache size exceeded: ${this.formatBytes(currentSize)} > ${this.formatBytes(config.imageCache.maxSize)}, cleaning old entries...`,
    );

    const sortedEntries = Array.from(this.manifest.entries())
      .sort(([, a], [, b]) => a.lastAccessedAt - b.lastAccessedAt);

    let freedSpace = 0;
    for (const [hash, entry] of sortedEntries) {
      if (currentSize - freedSpace <= config.imageCache.maxSize) break;

      const filePath = path.join(this.cacheDir, hash);
      try {
        if (existsSync(filePath)) {
          unlinkSync(filePath);
          freedSpace += entry.size;
        }
        this.manifest.delete(hash);
        console.log(`[ImageCache] Deleted cached image: ${entry.url} (${this.formatBytes(entry.size)})`);
      } catch (error) {
        console.error(`[ImageCache] Failed to delete image ${hash}:`, error);
      }
    }

    console.log(
      `[ImageCache] Freed up ${this.formatBytes(freedSpace)}. New cache size: ${this.formatBytes(this.getTotalSize())}`,
    );
    await this.saveManifest();
  }

  private formatBytes(bytes: number): string {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + ' ' + sizes[i];
  }

  async getCachedImageUrl(imageUrl: string): Promise<string | null> {
    if (!imageUrl) return null;

    const hash = this.generateHash(imageUrl);
    const entry = this.manifest.get(hash);

    if (entry) {
      entry.lastAccessedAt = Date.now();
      await this.saveManifest();
      return `/_cache/${hash}`;
    }

    return null;
  }

  async cacheImage(imageUrl: string): Promise<string> {
    if (!imageUrl) return imageUrl;

    const hash = this.generateHash(imageUrl);
    const existingEntry = this.manifest.get(hash);

    if (existingEntry) {
      existingEntry.lastAccessedAt = Date.now();
      await this.saveManifest();
      return `/_cache/${hash}`;
    }

    try {
      const imageBuffer = await this.fetchImage(imageUrl);
      const optimizedBuffer = await this.optimizeImage(imageBuffer);

      const filePath = path.join(this.cacheDir, hash);
      await writeFile(filePath, optimizedBuffer);

      const entry: CacheEntry = {
        url: imageUrl,
        contentHash: createHash('sha256').update(optimizedBuffer).digest('hex'),
        size: optimizedBuffer.length,
        createdAt: Date.now(),
        lastAccessedAt: Date.now(),
      };

      this.manifest.set(hash, entry);
      await this.saveManifest();

      console.log(
        `[ImageCache] Cached image: ${imageUrl} -> ${hash} (${this.formatBytes(entry.size)})`,
      );

      await this.enforceMaxSize();

      return `/_cache/${hash}`;
    } catch (error) {
      console.error(`[ImageCache] Failed to cache image ${imageUrl}:`, error);
      return imageUrl;
    }
  }

  private async fetchImage(url: string): Promise<Buffer> {
    const response = await fetch(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; WishlistBot/1.0)',
      },
      signal: AbortSignal.timeout(30000),
    });

    if (!response.ok) {
      throw new Error(`Failed to fetch image: HTTP ${response.status}`);
    }

    return Buffer.from(await response.arrayBuffer());
  }

  private async optimizeImage(buffer: Buffer): Promise<Buffer> {
    try {
      return await sharp(buffer)
        .rotate()
        .jpeg({ quality: 75, progressive: true })
        .toBuffer();
    } catch (error) {
      console.error('[ImageCache] Failed to optimize image, using original:', error);
      return buffer;
    }
  }

  async getImage(hash: string): Promise<Buffer | null> {
    const entry = this.manifest.get(hash);
    if (!entry) return null;

    const filePath = path.join(this.cacheDir, hash);
    try {
      const buffer = await readFile(filePath);
      entry.lastAccessedAt = Date.now();
      await this.saveManifest();
      return buffer;
    } catch (error) {
      console.error(`[ImageCache] Failed to read image ${hash}:`, error);
      this.manifest.delete(hash);
      await this.saveManifest();
      return null;
    }
  }

  async deleteImage(hash: string): Promise<void> {
    const filePath = path.join(this.cacheDir, hash);
    try {
      if (existsSync(filePath)) {
        await unlink(filePath);
      }
      this.manifest.delete(hash);
      await this.saveManifest();
    } catch (error) {
      console.error(`[ImageCache] Failed to delete image ${hash}:`, error);
    }
  }
}

export const imageCache = new ImageCache();
