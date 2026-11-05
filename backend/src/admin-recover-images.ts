/**
 * Recovery tool for items with corrupted cache URLs
 * 
 * Usage: node dist/admin-recover-images.js
 * 
 * This tool helps recover items that have cache URLs instead of original URLs.
 * It can:
 * 1. List all items with cache URLs
 * 2. Help restore original URLs from cache manifest
 * 3. Allow manual editing of URLs
 */

import * as readline from 'readline/promises';
import Database from 'better-sqlite3';
import { config } from './config.js';
import path from 'node:path';
import fs from 'node:fs';

const db = new Database(config.databaseFile);

async function main(): Promise<void> {
  console.log('\n🔍 Image URL Recovery Tool\n');
  console.log('This tool helps recover items that have cache URLs instead of original URLs.\n');

  const cacheDir = config.imageCache.dir;
  const manifestPath = path.join(cacheDir, 'manifest.json');

  // Read manifest
  let manifest: Record<string, any> = {};
  if (fs.existsSync(manifestPath)) {
    manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  }

  // Find items with cache URLs
  const items = db.prepare("SELECT id, title, image_url FROM items WHERE image_url LIKE '/_cache/%'").all() as any[];

  if (items.length === 0) {
    console.log('✓ No items with cache URLs found. Everything looks good!\n');
    db.close();
    return;
  }

  console.log(`⚠️  Found ${items.length} item(s) with cache URLs:\n`);

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    const hash = item.image_url.replace('/_cache/', '');
    const manifestEntry = manifest[hash];

    console.log(`\n[${i + 1}/${items.length}] ${item.title}`);
    console.log(`Current URL: ${item.image_url}`);

    if (manifestEntry) {
      console.log(`✓ Found in manifest!`);
      console.log(`Original URL: ${manifestEntry.url}`);

      const restore = await rl.question('Restore this URL? (y/n): ');
      if (restore.toLowerCase() === 'y') {
        db.prepare('UPDATE items SET image_url = ? WHERE id = ?').run(manifestEntry.url, item.id);
        console.log('✓ Restored!');
      }
    } else {
      console.log('✗ Not found in manifest. You need to enter the original URL manually.');

      const manualUrl = await rl.question('Enter original URL (or press Enter to skip): ');
      if (manualUrl) {
        db.prepare('UPDATE items SET image_url = ? WHERE id = ?').run(manualUrl, item.id);
        console.log('✓ Updated!');

        // Also update manifest for future reference
        manifest[hash] = {
          url: manualUrl,
          contentHash: '',
          size: fs.statSync(path.join(cacheDir, hash)).size,
          createdAt: Date.now(),
          lastAccessedAt: Date.now(),
        };
        fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
      } else {
        console.log('Skipped.');
      }
    }
  }

  rl.close();
  db.close();

  console.log('\n✓ Recovery complete!\n');
}

main().catch((error) => {
  console.error('Error:', error.message);
  db.close();
  process.exit(1);
});
