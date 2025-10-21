#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import path from 'node:path';
import process from 'node:process';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    ...options
  });
  if (result.status !== 0) {
    const stderr = result.stderr?.trim() ?? '';
    throw new Error(
      `Command ${command} ${args.join(' ')} failed with exit code ${result.status}${
        stderr ? `: ${stderr}` : ''
      }`
    );
  }
  return result.stdout.trim();
}

function parseRemoteUrl(url) {
  if (!url) {
    return null;
  }
  const sshMatch = url.match(/:(?<repoPath>[^/]+\/[^/]+)(?:\.git)?$/);
  const httpsMatch = url.match(/github\.com\/(?<repoPath>[^/]+\/[^/]+)(?:\.git)?$/);
  const repoPath = sshMatch?.groups?.repoPath ?? httpsMatch?.groups?.repoPath;
  if (!repoPath) {
    return null;
  }
  const [owner, repoRaw] = repoPath.split('/');
  if (!owner || !repoRaw) {
    return null;
  }
  const repo = repoRaw.endsWith('.git') ? repoRaw.slice(0, -4) : repoRaw;
  return { owner, repo };
}

function detectRepoRoot() {
  const result = spawnSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' });
  if (result.status !== 0) {
    throw new Error('Not inside a git repository (unable to detect repo root).');
  }
  return result.stdout.trim();
}

function pushBranch(repoRoot, branch) {
  const pushResult = spawnSync(
    'git',
    ['push', '--set-upstream', 'origin', branch],
    {
      cwd: repoRoot,
      stdio: 'inherit',
      encoding: 'utf8'
    }
  );
  if (pushResult.status !== 0) {
    throw new Error('Failed to push branch to origin. Resolve the push error above.');
  }
}

function ensureGhCli() {
  const result = spawnSync('gh', ['--version'], { encoding: 'utf8' });
  if (result.status !== 0) {
    throw new Error('GitHub CLI (gh) not found. Install gh and authenticate first.');
  }
}

function resolveUpstream(repoRoot) {
  try {
    const upstreamUrl = run(
      'git',
      ['config', '--get', 'remote.upstream.url'],
      { cwd: repoRoot }
    );
    const parsed = parseRemoteUrl(upstreamUrl);
    if (parsed) {
      return parsed;
    }
  } catch {}

  const envRepo = process.env.GITHUB_REPOSITORY;
  if (envRepo && envRepo.includes('/')) {
    const [owner, repo] = envRepo.split('/');
    return { owner, repo };
  }

  throw new Error(
    'Unable to determine upstream repository. Configure a remote named "upstream" or set GITHUB_REPOSITORY.'
  );
}

function resolveOrigin(repoRoot) {
  const originUrl = run('git', ['config', '--get', 'remote.origin.url'], { cwd: repoRoot });
  const parsed = parseRemoteUrl(originUrl);
  if (!parsed) {
    throw new Error(`Unable to parse origin remote URL: ${originUrl}`);
  }
  return parsed;
}

function getCurrentBranch(repoRoot) {
  const branch = run('git', ['rev-parse', '--abbrev-ref', 'HEAD'], { cwd: repoRoot });
  if (!branch || branch === 'HEAD') {
    throw new Error('Detached HEAD state detected; checkout a branch first.');
  }
  if (['develop', 'main'].includes(branch)) {
    throw new Error(`Refusing to open a PR directly from ${branch}. Create a feature branch first.`);
  }
  return branch;
}

function detectIssueNumber(repoRoot) {
  try {
    const cachePath = path.join(repoRoot, '.agent_priority_cache.json');
    const file = require(cachePath);
    if (file?.number) {
      return Number(file.number);
    }
  } catch {}
  return null;
}

function runGhPrCreate(upstream, origin, branch, base, extraArgs = []) {
  const args = [
    'pr',
    'create',
    '--repo',
    `${upstream.owner}/${upstream.repo}`,
    '--base',
    base,
    '--head',
    `${origin.owner}:${branch}`,
    '--fill',
    ...extraArgs
  ];

  const result = spawnSync('gh', args, { stdio: 'inherit', encoding: 'utf8' });
  if (result.status !== 0) {
    throw new Error('gh pr create failed. Review the messages above.');
  }
}

function main() {
  const repoRoot = detectRepoRoot();
  const branch = getCurrentBranch(repoRoot);
  const origin = resolveOrigin(repoRoot);
  const upstream = resolveUpstream(repoRoot);

  if (origin.owner === upstream.owner && origin.repo === upstream.repo) {
    throw new Error(
      'Origin remote matches upstream (not a fork). Configure a forked origin before using this script.'
    );
  }

  ensureGhCli();

  pushBranch(repoRoot, branch);

  const issueNumber = detectIssueNumber(repoRoot);
  const base = process.env.PR_BASE || 'develop';
  const extraArgs = [];

  if (issueNumber) {
    extraArgs.push('--title', `Update for standing priority #${issueNumber}`);
    extraArgs.push(
      '--body',
      `## Summary\n- (fill in summary)\n\n## Testing\n- (document testing)\n\nCloses #${issueNumber}`
    );
  }

  try {
    runGhPrCreate(upstream, origin, branch, base, extraArgs);
  } catch (error) {
    throw error;
  }
}

try {
  main();
} catch (error) {
  console.error(`[priority:create-pr] ${error.message}`);
  process.exitCode = 1;
}
