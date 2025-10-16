import test from 'node:test';
import assert from 'node:assert/strict';
import { parseGitRemoteUrl } from '../sync-standing-priority.mjs';

test('parseGitRemoteUrl handles SSH remotes', () => {
  const slug = parseGitRemoteUrl('git@github.com:LabVIEW-Community-CI-CD/compare-vi-cli-action.git');
  assert.equal(slug, 'LabVIEW-Community-CI-CD/compare-vi-cli-action');
});

test('parseGitRemoteUrl handles HTTPS remotes', () => {
  const slug = parseGitRemoteUrl('https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action.git');
  assert.equal(slug, 'LabVIEW-Community-CI-CD/compare-vi-cli-action');
});

test('parseGitRemoteUrl handles git+https repository URLs', () => {
  const slug = parseGitRemoteUrl('git+https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action.git');
  assert.equal(slug, 'LabVIEW-Community-CI-CD/compare-vi-cli-action');
});

test('parseGitRemoteUrl handles ssh protocol URLs', () => {
  const slug = parseGitRemoteUrl('ssh://git@github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action.git');
  assert.equal(slug, 'LabVIEW-Community-CI-CD/compare-vi-cli-action');
});

test('parseGitRemoteUrl returns null for invalid remotes', () => {
  assert.equal(parseGitRemoteUrl(''), null);
  assert.equal(parseGitRemoteUrl('not-a-remote'), null);
});
