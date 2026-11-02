import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const read = (file) => JSON.parse(readFileSync(path.join(root, file), 'utf8'));
const version = read('package.json').version;
const [mode, tag] = process.argv.slice(2);
assert.ok(['--sync', '--check'].includes(mode), 'Usage: version.mjs --sync | --check [release-tag]');
assert.match(version, /^\d+\.\d+\.\d+$/, 'The root package must have a release version');
if (tag) assert.equal(tag.replace(/^v/, ''), version, 'Release tag must match the package version');

if (mode === '--sync') {
  for (const prefix of ['.', 'backend', 'frontend']) {
    execFileSync('npm', [
      'version', version, '--prefix', prefix, '--no-git-tag-version', '--allow-same-version', '--ignore-scripts',
    ], { cwd: root, stdio: 'inherit' });
  }
}

for (const prefix of ['.', 'backend', 'frontend']) {
  const pkg = read(`${prefix}/package.json`);
  const lock = read(`${prefix}/package-lock.json`);
  for (const actual of [pkg.version, lock.version, lock.packages[''].version]) {
    assert.equal(actual, version, `${prefix} package and lockfile versions must match ${version}`);
  }
}
console.log(`All package and lockfile versions match ${version}${tag ? ` (${tag})` : ''}.`);
