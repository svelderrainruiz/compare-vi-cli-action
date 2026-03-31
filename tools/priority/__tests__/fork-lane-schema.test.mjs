#!/usr/bin/env node

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import yaml from 'js-yaml';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');

function loadJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(repoRoot, relativePath), 'utf8'));
}

function loadYaml(relativePath) {
  return yaml.load(fs.readFileSync(path.join(repoRoot, relativePath), 'utf8'));
}

function makeAjv() {
  const ajv = new Ajv2020({ allErrors: true, strict: false });
  addFormats(ajv);
  return ajv;
}

test('fork lane instance schema validates the issue-specific manifest and the reusable template', () => {
  const schema = loadJson('docs/schemas/fork-lane-instance-v1.schema.json');
  const validate = makeAjv().compile(schema);

  for (const relativePath of [
    'tools/priority/fork-lanes/template.yaml',
    'tools/priority/fork-lanes/issue-2078.yaml'
  ]) {
    const document = loadYaml(relativePath);
    assert.equal(validate(document), true, `${relativePath} failed schema validation:\n${JSON.stringify(validate.errors, null, 2)}`);
    const selected = document.forks.selected;
    const fork = document.forks.catalog.find((item) => item.id === selected);
    assert.ok(fork, `${relativePath} missing selected fork '${selected}'`);
    assert.equal(typeof fork.push_enabled, 'boolean');
    assert.equal(typeof fork.mount_allowed, 'boolean');
  }
});

test('fork lane index schema tracks the active issue and checked-in instance path', () => {
  const schema = loadJson('docs/schemas/fork-lane-index-v1.schema.json');
  const validate = makeAjv().compile(schema);
  const index = loadYaml('tools/priority/fork-lanes/index.yaml');

  assert.equal(validate(index), true, JSON.stringify(validate.errors, null, 2));
  assert.equal(index.active_issue, 2078);

  const entry = index.instances.find((item) => item.issue_number === 2078);
  assert.ok(entry, 'expected active instance entry for issue 2078');
  assert.equal(entry.path, 'tools/priority/fork-lanes/issue-2078.yaml');
  assert.equal(entry.selected_fork_id, 'personal');
  assert.deepEqual(entry.fork_repositories, [
    'svelderrainruiz/compare-vi-cli-action',
    'LabVIEW-Community-CI-CD/compare-vi-cli-action-fork'
  ]);
  assert.equal(fs.existsSync(path.join(repoRoot, entry.path)), true);
});
