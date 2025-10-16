import test from 'node:test';
import assert from 'node:assert/strict';
import { shouldWriteCache } from '../sync-standing-priority.mjs';

const baseCache = {
  number: 134,
  title: 'Standing priority',
  url: 'https://example.test/134',
  cachedAtUtc: '2025-10-16T19:19:36.942Z',
  state: 'OPEN',
  lastSeenUpdatedAt: '2025-10-15T18:04:17Z',
  issueDigest: 'digest',
  labels: [],
  assignees: [],
  milestone: null,
  commentCount: null,
  bodyDigest: null,
  lastFetchSource: 'cache',
  lastFetchError: 'gh CLI not found'
};

test('shouldWriteCache returns true when no previous cache exists', () => {
  const next = { ...baseCache, cachedAtUtc: '2025-10-16T20:11:24.858Z' };
  assert.equal(shouldWriteCache(null, next), true);
});

test('shouldWriteCache ignores cachedAtUtc-only differences', () => {
  const next = { ...baseCache, cachedAtUtc: '2025-10-16T20:11:24.858Z' };
  assert.equal(shouldWriteCache(baseCache, next), false);
});

test('shouldWriteCache detects meaningful differences', () => {
  const next = { ...baseCache, lastFetchSource: 'live' };
  assert.equal(shouldWriteCache(baseCache, next), true);
});
