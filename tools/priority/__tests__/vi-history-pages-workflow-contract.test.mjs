#!/usr/bin/env node

import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { readFileSync } from 'node:fs';

const repoRoot = process.cwd();

function readRepoFile(relativePath) {
  return readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('publish vi history pages workflow supports manual and validate-driven publication', () => {
  const workflow = readRepoFile('.github/workflows/publish-vi-history-pages.yml');

  assert.match(workflow, /name:\s+Publish VI History Pages/);
  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /source_run_id:/);
  assert.match(workflow, /source_artifact_name:/);
  assert.match(workflow, /preserve_existing_catalog:/);
  assert.match(workflow, /publish:/);
  assert.match(workflow, /workflow_run:\s*\r?\n\s+workflows:\s+\[Validate\]\s*\r?\n\s+types:\s+\[completed\]/);
});

test('publish vi history pages workflow downloads source artifacts and runs the typed builders', () => {
  const workflow = readRepoFile('.github/workflows/publish-vi-history-pages.yml');

  assert.match(workflow, /actions\/download-artifact@v5/);
  assert.match(workflow, /run-id:\s+\$\{\{\s*steps\.ctx\.outputs\.source_run_id\s*\}\}/);
  assert.match(workflow, /repository:\s+\$\{\{\s*steps\.ctx\.outputs\.source_repository\s*\}\}/);
  assert.match(workflow, /history:pages:build/);
  assert.match(workflow, /history:pages:catalog/);
  assert.match(workflow, /--existing-catalog-url/);
  assert.match(workflow, /vi-history-pages-publication-v1\.schema\.json/);
  assert.match(workflow, /vi-history-pages-catalog-v1\.schema\.json/);
});

test('publish vi history pages workflow keeps deployment thin', () => {
  const workflow = readRepoFile('.github/workflows/publish-vi-history-pages.yml');

  assert.match(workflow, /Upload prepared Pages site artifact/);
  assert.match(workflow, /actions\/upload-pages-artifact@56afc609e74202658d3ffba0e8f6dda462b719fa/);
  assert.match(workflow, /actions\/deploy-pages@d6db90164ac5ed86f2b6aed7e0febac5b3c0c03e/);
  assert.match(workflow, /environment:\s*\r?\n\s+name:\s+github-pages/);
});
