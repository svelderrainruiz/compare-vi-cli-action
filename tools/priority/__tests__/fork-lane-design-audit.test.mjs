#!/usr/bin/env node

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { runForkLaneDesignAudit } from '../fork-lane-design-audit.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');

function loadJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(repoRoot, relativePath), 'utf8'));
}

test('fork lane design audit produces a standards-grounded report with action items', async () => {
  const outputPath = path.join('tests', 'results', '_agent', 'fork-lanes', 'fork-lane-design-audit-report.test.json');
  const summaryPath = path.join('tests', 'results', '_agent', 'fork-lanes', 'fork-lane-design-audit-summary.test.md');
  const { report } = await runForkLaneDesignAudit({
    repoRoot,
    outputPath,
    summaryPath
  });

  const schema = loadJson('docs/schemas/fork-lane-design-audit-report-v1.schema.json');
  const ajv = new Ajv2020({ allErrors: true, strict: false });
  addFormats(ajv);
  const validate = ajv.compile(schema);
  assert.equal(validate(report), true, JSON.stringify(validate.errors, null, 2));

  assert.equal(report.overall.status, 'pass-with-actions');
  assert.ok(report.findings.some((finding) => finding.id === 'fork-capability-contract' && finding.status === 'finding'));
  assert.ok(report.findings.some((finding) => finding.id === 'lifecycle-closure-contract' && finding.status === 'finding'));
  assert.ok(report.findings.some((finding) => finding.id === 'index-reconciliation' && finding.status === 'pass'));
  assert.ok(report.actionItems.some((item) => item.id === 'add-fork-capability-attributes'));
  assert.ok(report.actionItems.some((item) => item.id === 'add-lifecycle-closure-rules'));
});
