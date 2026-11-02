import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { it } from 'node:test';
import sharp from 'sharp';

const root = fileURLToPath(new URL('../', import.meta.url));
const read = (file) => readFileSync(path.join(root, file));
const json = (file) => JSON.parse(read(file).toString());
const catalog = 'ios/App/App/Assets.xcassets';

function assertPng(file, size, transparent = false) {
  const png = read(file);
  assert.equal(png.subarray(0, 8).toString('hex'), '89504e470d0a1a0a', `${file} must be a PNG`);
  assert.equal(png.readUInt32BE(16), size, `${file} width`);
  assert.equal(png.readUInt32BE(20), size, `${file} height`);
  assert.equal(png[24], 8, `${file} must have 8-bit channels`);
  assert.equal(png[25], transparent ? 6 : 2, `${file} must ${transparent ? 'have' : 'not have'} an alpha channel`);
  assert.ok(png.length > 200, `${file} must contain rendered artwork`);
}

it('renders a visible white gift and gold sparkle on purple, not a blank or black icon', async () => {
  for (const file of [
    'src/assets/icon/favicon.png',
    'src/assets/icon/apple-touch-icon.png',
    'src/assets/icon/icon-192.png',
    'src/assets/icon/icon-512.png',
    `${catalog}/AppIcon.appiconset/AppIcon-512@2x.png`,
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

it('renders the launch logo with a visible gift and a transparent background', async () => {
  const { data, info } = await sharp(read(`${catalog}/LaunchLogo.imageset/logo@2x.png`))
    .ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  assert.equal(data[3], 0);
  let visibleWhite = 0;
  for (let index = 0; index < data.length; index += 4) {
    if (data[index] > 240 && data[index + 1] > 240 && data[index + 2] > 240 && data[index + 3] > 240) visibleWhite++;
  }
  assert.ok(visibleWhite / (info.width * info.height) > 0.05);
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

it('provides the opaque 1024px native app icon required by iOS', () => {
  const icons = json(`${catalog}/AppIcon.appiconset/Contents.json`);
  assert.equal(icons.images.length, 1);
  assert.equal(icons.images[0].size, '1024x1024');
  assertPng(`${catalog}/AppIcon.appiconset/${icons.images[0].filename}`, 1024);
});

it('wires the launch screen to centered artwork at all three native scales', () => {
  const storyboard = read('ios/App/App/Base.lproj/LaunchScreen.storyboard').toString();
  assert.match(storyboard, /image="LaunchLogo"/);
  assert.match(storyboard, /contentMode="scaleAspectFit"/);
  assert.match(storyboard, /firstAttribute="centerX"/);
  assert.match(storyboard, /firstAttribute="centerY"/);
  assert.doesNotMatch(storyboard, /image="Splash"/);
  const images = json(`${catalog}/LaunchLogo.imageset/Contents.json`).images;
  assert.deepEqual(images.map((image) => image.scale), ['1x', '2x', '3x']);
  for (const image of images) {
    assertPng(`${catalog}/LaunchLogo.imageset/${image.filename}`, 224 * Number.parseInt(image.scale, 10), true);
  }
});
