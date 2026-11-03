import { mkdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const root = fileURLToPath(new URL('../', import.meta.url));
const source = readFileSync(path.join(root, 'src/assets/icon/app-icon.svg'), 'utf8');

const images = [
  ['src/assets/icon/favicon.png', 32],
  ['src/assets/icon/apple-touch-icon.png', 180],
  ['src/assets/icon/icon-192.png', 192],
  ['src/assets/icon/icon-512.png', 512],
];

for (const [file, size] of images) {
  const destination = path.join(root, file);
  mkdirSync(path.dirname(destination), { recursive: true });
  await sharp(Buffer.from(source))
    .resize(size, size)
    .flatten({ background: '#5b47d1' })
    .removeAlpha()
    .png()
    .toFile(destination);
  console.log(`Generated ${file} (${size}x${size})`);
}
