import test from 'node:test';
import assert from 'node:assert/strict';
import { resolveRepoContext } from '../lib/git-context.mjs';

const upstreamSlug = { owner: 'LabVIEW-Community-CI-CD', repo: 'compare-vi-cli-action' };

test('resolveRepoContext detects fork when origin owner differs from upstream', () => {
  const context = resolveRepoContext('repo', {
    resolveUpstreamFn: () => upstreamSlug,
    resolveRemoteFn: (_root, name) => {
      if (name === 'origin') {
        return { parsed: { owner: 'user-fork', repo: upstreamSlug.repo } };
      }
      if (name === 'upstream') {
        return { parsed: upstreamSlug };
      }
      return null;
    },
    env: {}
  });

  assert.equal(context.isFork, true);
  const expectedFork = { owner: 'user-fork', repo: upstreamSlug.repo };
  assert.deepEqual(context.origin, expectedFork);
  assert.deepEqual(context.working, expectedFork);
  assert.deepEqual(context.upstream, upstreamSlug);
});

test('resolveRepoContext treats same-owner origin as upstream (not a fork)', () => {
  const context = resolveRepoContext('repo', {
    resolveUpstreamFn: () => upstreamSlug,
    resolveRemoteFn: (_root, name) => {
      if (name === 'origin' || name === 'upstream') {
        return { parsed: upstreamSlug };
      }
      return null;
    },
    env: {}
  });

  assert.equal(context.isFork, false);
  assert.deepEqual(context.working, upstreamSlug);
});

test('resolveRepoContext falls back to env repository when origin remote missing', () => {
  const context = resolveRepoContext('repo', {
    resolveUpstreamFn: () => upstreamSlug,
    resolveRemoteFn: () => null,
    env: {
      GITHUB_REPOSITORY: 'user-alt/compare-vi-cli-action'
    }
  });

  assert.equal(context.isFork, true);
  assert.equal(context.working.owner, 'user-alt');
  assert.deepEqual(context.upstream, upstreamSlug);
});
