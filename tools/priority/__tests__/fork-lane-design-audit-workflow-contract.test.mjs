#!/usr/bin/env node

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');

function readRepoFile(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('fork lane design audit workflow runs hosted CI over the fork-lane control-plane files', () => {
  const workflow = readRepoFile('.github/workflows/fork-lane-design-audit.yml');

  assert.match(workflow, /name:\s+Fork lane design audit/);
  assert.match(workflow, /push:/);
  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /tools\/priority\/fork-lanes\/\*\*/);
  assert.match(workflow, /docs\/schemas\/fork-lane-/);
  assert.match(workflow, /runs-on:\s+ubuntu-latest/);
  assert.match(workflow, /node tools\/npm\/cli\.mjs ci/);
  assert.match(workflow, /node --test tools\/priority\/__tests__\/fork-lane-schema\.test\.mjs tools\/priority\/__tests__\/fork-lane-design-audit\.test\.mjs/);
  assert.match(workflow, /node tools\/priority\/fork-lane-design-audit\.mjs/);
  assert.match(workflow, /upload-artifact@v7/);
});
