import test from 'node:test';
import assert from 'node:assert/strict';
import { parseArgs, sanitizeSlug } from '../rename-issue-branch.mjs';

test('parseArgs captures required and optional flags', () => {
  const parsed = parseArgs([
    'node',
    'rename-issue-branch.mjs',
    '--issue',
    '496',
    '--branch',
    'issue/491-release-alignment',
    '--slug',
    'custom-slug',
    '--keep-remote',
    '--skip-pr'
  ]);

  assert.equal(parsed.issue, 496);
  assert.equal(parsed.branch, 'issue/491-release-alignment');
  assert.equal(parsed.slugOverride, 'custom-slug');
  assert.equal(parsed.keepRemote, true);
  assert.equal(parsed.skipPr, true);
  assert.equal(parsed.help, false);
});

test('parseArgs sets help flag when requested', () => {
  const parsed = parseArgs(['node', 'rename-issue-branch.mjs', '--help']);
  assert.equal(parsed.help, true);
});

test('sanitizeSlug normalises titles into ascii slugs', () => {
  assert.equal(sanitizeSlug('Add new feature!'), 'add-new-feature');
  assert.equal(sanitizeSlug('  Café Δelta tests  '), 'cafe-elta-tests');
  assert.equal(sanitizeSlug('???'), 'work');
});
