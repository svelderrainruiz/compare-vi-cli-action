#!/usr/bin/env node

import test from 'node:test';
import assert from 'node:assert/strict';
import { buildCoberturaXml, extractCoverageMetrics } from '../write-node-test-coverage-xml.mjs';

test('extractCoverageMetrics parses aggregate node coverage summary', () => {
  const sample = `
ℹ start of coverage report
ℹ ----------------------------------------------------------
ℹ file      | line % | branch % | funcs % | uncovered lines
ℹ ----------------------------------------------------------
ℹ ----------------------------------------------------------
ℹ all files | 100.00 |   87.50 |  92.30 |
ℹ ----------------------------------------------------------
ℹ end of coverage report
`;
  const metrics = extractCoverageMetrics(sample);
  assert.deepEqual(metrics, {
    lineRatePercent: 100,
    branchRatePercent: 87.5,
    functionRatePercent: 92.3
  });
});

test('buildCoberturaXml writes aggregate line and branch rates', () => {
  const xml = buildCoberturaXml({
    lineRatePercent: 100,
    branchRatePercent: 87.5,
    functionRatePercent: 92.3,
    lineThreshold: 75
  });
  assert.match(xml, /line-rate="1.0000"/);
  assert.match(xml, /branch-rate="0.8750"/);
  assert.match(xml, /thresholds line="75"/);
});
