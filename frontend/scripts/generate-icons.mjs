import { mkdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const root = fileURLToPath(new URL('../', import.meta.url));
const source = readFileSync(path.join(root, 'src/assets/icon/app-icon.svg'), 'utf8');
const launchSource = source.replace(/<rect id="background"[^>]*\/>/, '');
if (launchSource === source) throw new Error('The icon source must have a removable background rectangle');

const images = [
  ['src/assets/icon/favicon.png', 32, false],
  ['src/assets/icon/apple-touch-icon.png', 180, false],
  ['src/assets/icon/icon-192.png', 192, false],
  ['src/assets/icon/icon-512.png', 512, false],
  ['ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png', 1024, false],
  ['ios/App/App/Assets.xcassets/LaunchLogo.imageset/logo.png', 224, true],
  ['ios/App/App/Assets.xcassets/LaunchLogo.imageset/logo@2x.png', 448, true],
  ['ios/App/App/Assets.xcassets/LaunchLogo.imageset/logo@3x.png', 672, true],
];

for (const [file, size, transparent] of images) {
  const destination = path.join(root, file);
  mkdirSync(path.dirname(destination), { recursive: true });
  const image = sharp(Buffer.from(transparent ? launchSource : source)).resize(size, size);
  if (transparent) image.ensureAlpha();
  else image.flatten({ background: '#5b47d1' }).removeAlpha();
  await image.png().toFile(destination);
  console.log(`Generated ${file} (${size}x${size})`);
}
