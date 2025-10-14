import test from 'node:test';
import assert from 'node:assert/strict';
import { detectPlane, resolveEnforcement } from '../core/runner.mjs';

test('detectPlane detects GitHub Ubuntu', () => {
  const plane = detectPlane({ platform: 'linux', env: { GITHUB_ACTIONS: 'true' } });
  assert.equal(plane, 'github-ubuntu');
});

test('detectPlane detects GitHub Windows', () => {
  const plane = detectPlane({ platform: 'win32', env: { GITHUB_ACTIONS: 'true' } });
  assert.equal(plane, 'github-windows');
});

test('detectPlane detects WSL', () => {
  const plane = detectPlane({ platform: 'linux', env: { WSL_DISTRO_NAME: 'Ubuntu-22.04' } });
  assert.equal(plane, 'linux-wsl');
});

test('detectPlane detects macOS', () => {
  const plane = detectPlane({ platform: 'darwin', env: {} });
  assert.equal(plane, 'macos-bash');
});

test('detectPlane defaults to linux bash', () => {
  const plane = detectPlane({ platform: 'linux', env: {} });
  assert.equal(plane, 'linux-bash');
});

test('resolveEnforcement respects explicit env', () => {
  const mode = resolveEnforcement({ env: { HOOKS_ENFORCE: 'off' } });
  assert.equal(mode, 'off');
});

test('resolveEnforcement defaults to fail on CI', () => {
  const mode = resolveEnforcement({ env: { GITHUB_ACTIONS: 'true' } });
  assert.equal(mode, 'fail');
});

test('resolveEnforcement defaults to warn locally', () => {
  const mode = resolveEnforcement({ env: {} });
  assert.equal(mode, 'warn');
});
