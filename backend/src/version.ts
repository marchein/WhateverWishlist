import { readFileSync } from 'node:fs';

const pkg: { version: string } = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
export const version = pkg.version;
