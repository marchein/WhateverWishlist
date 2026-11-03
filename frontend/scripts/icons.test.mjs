import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { it } from 'node:test';
import sharp from 'sharp';

const root = fileURLToPath(new URL('../', import.meta.url));
const read = (file) => readFileSync(path.join(root, file));
const json = (file) => JSON.parse(read(file).toString());

function assertPng(file, size) {
  const png = read(file);
  assert.equal(png.subarray(0, 8).toString('hex'), '89504e470d0a1a0a', `${file} must be a PNG`);
  assert.equal(png.readUInt32BE(16), size, `${file} width`);
  assert.equal(png.readUInt32BE(20), size, `${file} height`);
  assert.equal(png[24], 8, `${file} must have 8-bit channels`);
  assert.equal(png[25], 2, `${file} must not have an alpha channel`);
  assert.ok(png.length > 200, `${file} must contain rendered artwork`);
}

it('renders a visible white gift and gold sparkle on purple, not a blank or black icon', async () => {
  for (const file of [
    'src/assets/icon/favicon.png',
    'src/assets/icon/apple-touch-icon.png',
    'src/assets/icon/icon-192.png',
    'src/assets/icon/icon-512.png',
  ]) {
    const { data, info } = await sharp(read(file)).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    const pixels = info.width * info.height;
    let white = 0;
    let gold = 0;
    for (let index = 0; index < data.length; index += 4) {
      const [r, g, b, a] = data.subarray(index, index + 4);
      assert.equal(a, 255, `${file} must be fully opaque`);
      if (r > 240 && g > 240 && b > 240) white++;
      if (r > 230 && g > 170 && g < 235 && b < 170) gold++;
    }
    assert.ok(white / pixels > 0.05, `${file} must visibly contain the white gift`);
    assert.ok(gold / pixels > 0.001, `${file} must visibly contain the gold sparkle`);
    assert.ok(data[2] > data[0] + 50 && data[2] > data[1] + 50, `${file} must have a purple, not black, background`);
  }
});

it('provides a vector favicon, PNG fallback and correctly sized Apple home-screen icon', () => {
  const html = read('src/index.html').toString();
  for (const file of ['app-icon.svg', 'favicon.png', 'apple-touch-icon.png', 'site.webmanifest']) {
    assert.ok(html.includes(`assets/icon/${file}`), `HTML must link ${file}`);
  }
  assert.match(read('src/assets/icon/app-icon.svg').toString(), /WhateverWishlist/);
  assertPng('src/assets/icon/favicon.png', 32);
  assertPng('src/assets/icon/apple-touch-icon.png', 180);
});

it('provides installable web icon metadata with matching image dimensions', () => {
  const manifest = json('src/assets/icon/site.webmanifest');
  assert.equal(manifest.start_url, '/');
  assert.equal(manifest.display, 'standalone');
  assert.equal(manifest.background_color, manifest.theme_color);
  for (const icon of manifest.icons) {
    const size = Number(icon.sizes.split('x')[0]);
    assertPng(`src/assets/icon/${icon.src}`, size);
  }
});
