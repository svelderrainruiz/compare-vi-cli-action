import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeSummary } from '../core/summary-utils.mjs';

test('normalizeSummary zeroes timestamp and duration and sorts steps', () => {
  const input = {
    schema: 'comparevi/hooks-summary@v1',
    hook: 'pre-commit',
    timestamp: '2025-10-13T12:34:56Z',
    steps: [
      { name: 'b-step', durationMs: 42, status: 'ok' },
      { name: 'a-step', durationMs: 5, status: 'ok' },
    ],
  };

  const normalized = normalizeSummary(input);

  assert.equal(normalized.timestamp, 'normalized');
  assert.deepEqual(
    normalized.steps,
    [
      { name: 'a-step', durationMs: 0, status: 'ok' },
      { name: 'b-step', durationMs: 0, status: 'ok' },
    ],
  );

  // Ensure original input not mutated
  assert.equal(input.timestamp, '2025-10-13T12:34:56Z');
  assert.equal(input.steps[0].durationMs, 42);
});
