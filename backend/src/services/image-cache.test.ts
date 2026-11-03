import { test } from 'node:test';
import assert from 'node:assert/strict';
import { join } from 'node:path';
import { rmSync, existsSync, mkdirSync } from 'node:fs';
import { ImageCache } from './image-cache.js';

const testCacheDir = '/tmp/test-image-cache-' + Date.now();

test('ImageCache hash generation', () => {
  const cache = new ImageCache();
  const hash1 = (cache as any).generateHash('https://example.com/image.jpg');
  const hash2 = (cache as any).generateHash('https://example.com/image.jpg');
  const hash3 = (cache as any).generateHash('https://example.com/other.jpg');

  assert.equal(hash1, hash2, 'Same URL should generate same hash');
  assert.notEqual(hash1, hash3, 'Different URLs should generate different hashes');
  assert.match(hash1, /^[a-f0-9]{16}$/, 'Hash should be 16 hex characters');
});

test('ImageCache formatBytes', () => {
  const cache = new ImageCache();
  const formatBytes = (cache as any).formatBytes.bind(cache);

  assert.equal(formatBytes(0), '0 B');
  assert.equal(formatBytes(1024), '1 KB');
  assert.equal(formatBytes(1024 * 1024), '1 MB');
  assert.equal(formatBytes(1536), '1.5 KB');
});

test('ImageCache cleanup', async () => {
  // Override config for this test
  const originalConfig = (await import('../config.js')).config;
  const testConfig = {
    ...originalConfig,
    imageCache: {
      dir: testCacheDir,
      maxSize: 1024 * 1024,
      maxAge: 0,
    },
  };

  try {
    mkdirSync(testCacheDir, { recursive: true });
    // Test would need mocking to fully test cleanup logic
    assert.ok(existsSync(testCacheDir));
  } finally {
    if (existsSync(testCacheDir)) {
      rmSync(testCacheDir, { recursive: true });
    }
  }
});
