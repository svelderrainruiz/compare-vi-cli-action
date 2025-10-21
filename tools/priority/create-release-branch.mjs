#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    ...options
  });
  if (result.status !== 0) {
    const stderr = result.stderr?.trim() ?? '';
    throw new Error(
      `${command} ${args.join(' ')} exited with ${result.status}${stderr ? `: ${stderr}` : ''}`
    );
  }
  return result.stdout.trim();
}

function tryRun(command, args, options = {}) {
  return spawnSync(command, args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    ...options
  });
}

function parseRemoteUrl(url) {
  if (!url) return null;
  const sshMatch = url.match(/:(?<repoPath>[^/]+\/[^/]+)(?:\.git)?$/);
  const httpsMatch = url.match(/github\.com\/(?<repoPath>[^/]+\/[^/]+)(?:\.git)?$/);
  const repoPath = sshMatch?.groups?.repoPath ?? httpsMatch?.groups?.repoPath;
  if (!repoPath) return null;
  const [owner, repoRaw] = repoPath.split('/');
  if (!owner || !repoRaw) return null;
  const repo = repoRaw.endsWith('.git') ? repoRaw.slice(0, -4) : repoRaw;
  return { owner, repo };
}

function repoRoot() {
  return run('git', ['rev-parse', '--show-toplevel']);
}

function ensureCleanWorkingTree(root) {
  const status = run('git', ['status', '--porcelain'], { cwd: root });
  if (status.trim().length > 0) {
    throw new Error('Working tree not clean. Commit, stash, or clean changes before creating a release branch.');
  }
}

function ensureOnBranch(root, expected) {
  const branch = run('git', ['rev-parse', '--abbrev-ref', 'HEAD'], { cwd: root });
  if (branch !== expected) {
    throw new Error(`Release branches must start from ${expected}. Current branch: ${branch}`);
  }
}

function ensureGhCli() {
  const result = tryRun('gh', ['--version']);
  if (result.status !== 0) {
    throw new Error('GitHub CLI (gh) not found. Install gh and authenticate first.');
  }
}

function tryResolveRemote(root, remoteName) {
  try {
    const url = run('git', ['config', '--get', `remote.${remoteName}.url`], { cwd: root });
    return { url, parsed: parseRemoteUrl(url) };
  } catch {
    return null;
  }
}

function ensureOriginFork(root, upstream) {
  let origin = tryResolveRemote(root, 'origin');
  if (!origin?.parsed || origin.parsed.owner === upstream.owner) {
    console.log('[release:branch] ensuring origin remote points to fork (gh repo fork)');
    const args = [
      'repo',
      'fork',
      `${upstream.owner}/${upstream.repo}`,
      '--remote',
      '--remote-name',
      'origin'
    ];
    const result = spawnSync('gh', args, { cwd: root, stdio: 'inherit', encoding: 'utf8' });
    if (result.status !== 0) {
      throw new Error('Failed to fork repository or set origin remote.');
    }
    origin = tryResolveRemote(root, 'origin');
  }
  if (!origin?.parsed || origin.parsed.owner === upstream.owner) {
    throw new Error('Origin remote still points to upstream. Confirm fork permissions and retry.');
  }
  return origin.parsed;
}

function upstreamRemote(root) {
  const upstream = tryResolveRemote(root, 'upstream');
  if (upstream?.parsed) {
    return upstream.parsed;
  }
  const envRepo = process.env.GITHUB_REPOSITORY;
  if (envRepo && envRepo.includes('/')) {
    const [owner, repo] = envRepo.split('/');
    return { owner, repo };
  }
  throw new Error('Unable to determine upstream remote. Configure `upstream` or set GITHUB_REPOSITORY.');
}

function createReleaseBranch(root, version, base) {
  const branchName = `release/${version}`;
  const existing = tryRun('git', ['rev-parse', '--verify', branchName], { cwd: root });
  if (existing.status === 0) {
    throw new Error(`Branch ${branchName} already exists.`);
  }
  run('git', ['checkout', '-b', branchName, base], { cwd: root });
  return branchName;
}

async function writeMetadata(root, branch, version, base, commit) {
  const dir = path.join(root, 'tests', 'results', '_agent', 'release');
  await mkdir(dir, { recursive: true });
  const payload = {
    schema: 'release/branch@v1',
    branch,
    version,
    baseBranch: base,
    baseCommit: commit,
    createdAt: new Date().toISOString()
  };
  const file = path.join(dir, `release-${version}.json`);
  await writeFile(file, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
  console.log(`[release:branch] recorded metadata -> ${file}`);
}

function pushBranch(root, branch) {
  const result = spawnSync(
    'git',
    ['push', '--set-upstream', 'origin', branch],
    { cwd: root, stdio: 'inherit', encoding: 'utf8' }
  );
  if (result.status !== 0) {
    throw new Error('Failed to push release branch to origin. Resolve the push failure above.');
  }
}

function openPullRequest(upstream, origin, branch, version) {
  const args = [
    'pr',
    'create',
    '--repo',
    `${upstream.owner}/${upstream.repo}`,
    '--base',
    'main',
    '--head',
    `${origin.owner}:${branch}`,
    '--title',
    `Prepare release ${version}`,
    '--body',
    `## Summary
- Prepare release ${version}
- TODO: add changelog / version updates

## Testing
- TODO`
  ];
  const result = spawnSync('gh', args, { stdio: 'inherit', encoding: 'utf8' });
  if (result.status !== 0) {
    throw new Error('Failed to open pull request via gh.');
  }
}

async function main() {
  const [, , versionArg] = process.argv;
  if (!versionArg) {
    console.error('Usage: npm run release:branch -- vX.Y.Z');
    process.exit(1);
    return;
  }
  const version = versionArg.trim();
  const root = repoRoot();

  ensureCleanWorkingTree(root);
  ensureOnBranch(root, 'develop');
  ensureGhCli();

  const upstream = upstreamRemote(root);
  const origin = ensureOriginFork(root, upstream);
  const baseCommit = run('git', ['rev-parse', 'HEAD'], { cwd: root });

  const branch = createReleaseBranch(root, version, 'HEAD');
  await writeMetadata(root, branch, version, 'develop', baseCommit);

  console.log(`[release:branch] release branch ${branch} created from develop@${baseCommit.slice(0, 7)}.`);

  pushBranch(root, branch);
  openPullRequest(upstream, origin, branch, version);
}

main().catch((error) => {
  console.error(`[release:branch] ${error.message}`);
  process.exitCode = 1;
});
