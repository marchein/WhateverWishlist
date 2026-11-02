import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, beforeEach, it } from 'node:test';

let root;
const write = (file, value) => writeFileSync(path.join(root, file), JSON.stringify(value));
const run = (...args) => spawnSync(process.execPath, ['scripts/version.mjs', ...args], {
  cwd: root, encoding: 'utf8',
});

beforeEach(() => {
  root = mkdtempSync(path.join(tmpdir(), 'wishlist-version-'));
  mkdirSync(path.join(root, 'scripts'));
  copyFileSync(new URL('./version.mjs', import.meta.url), path.join(root, 'scripts/version.mjs'));
  for (const prefix of ['.', 'backend', 'frontend']) {
    mkdirSync(path.join(root, prefix), { recursive: true });
    write(`${prefix}/package.json`, {
      name: prefix === '.' ? 'wishlist' : prefix,
      version: '1.0.3',
      private: true,
      ...(prefix === '.' ? { scripts: { version: 'node scripts/version.mjs --sync' } } : {}),
    });
    write(`${prefix}/package-lock.json`, {
      version: '1.0.3', lockfileVersion: 3, packages: { '': { version: '1.0.3' } },
    });
  }
});

afterEach(() => {
  rmSync(root, { recursive: true });
});

it('accepts a tag matching every package and lockfile version', () => {
  const result = run('--check', 'v1.0.3');
  assert.equal(result.status, 0, result.stderr);
});

it('rejects a release tag that does not match the packages', () => {
  const result = run('--check', 'v1.0.4');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Release tag must match/);
});

it('rejects a stale backend package version', () => {
  write('backend/package.json', { version: '0.1.0' });
  const result = run('--check', 'v1.0.3');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /backend package and lockfile versions must match/);
});

it('rejects an out-of-sync lockfile root package version', () => {
  write('frontend/package-lock.json', {
    version: '1.0.3', packages: { '': { version: '1.0.2' } },
  });
  assert.notEqual(run('--check', 'v1.0.3').status, 0);
});

it('synchronizes all packages and locks through the root npm version lifecycle', () => {
  const bump = spawnSync('npm', ['version', '1.0.4', '--no-git-tag-version'], {
    cwd: root, encoding: 'utf8',
  });
  assert.equal(bump.status, 0, bump.stderr);
  const check = run('--check', 'v1.0.4');
  assert.equal(check.status, 0, check.stderr);
});
