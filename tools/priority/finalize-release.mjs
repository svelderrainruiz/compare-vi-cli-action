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

function repoRoot() {
  return run('git', ['rev-parse', '--show-toplevel']);
}

function ensureCleanWorkingTree(root) {
  const status = run('git', ['status', '--porcelain'], { cwd: root });
  if (status.trim().length > 0) {
    throw new Error('Working tree not clean. Commit or stash changes before finalizing the release.');
  }
}

function ensureGhCli() {
  const result = tryRun('gh', ['--version']);
  if (result.status !== 0) {
    throw new Error('GitHub CLI (gh) not found. Install gh and authenticate first.');
  }
}

function releaseBranchExists(root, branch) {
  const result = tryRun('git', ['show-ref', '--verify', `refs/heads/${branch}`], { cwd: root });
  return result.status === 0;
}

function checkoutBranch(root, branch) {
  run('git', ['checkout', branch], { cwd: root });
}

function fetchUpstream(root) {
  run('git', ['fetch', 'upstream'], { cwd: root });
}

async function writeFinalizeMetadata(root, version, data) {
  const dir = path.join(root, 'tests', 'results', '_agent', 'release');
  await mkdir(dir, { recursive: true });
  const file = path.join(dir, `release-${version}-finalize.json`);
  await writeFile(file, `${JSON.stringify(data, null, 2)}\n`, 'utf8');
  console.log(`[release:finalize] wrote metadata -> ${file}`);
}

function mergeFastForward(root, targetBranch, sourceBranch) {
  checkoutBranch(root, targetBranch);
  run('git', ['pull', 'upstream', targetBranch], { cwd: root });
  run('git', ['merge', '--ff-only', sourceBranch], { cwd: root });
  run('git', ['push', 'upstream', targetBranch], { cwd: root });
}

function createDraftRelease(root, version) {
  const args = [
    'release',
    'create',
    version,
    '--draft',
    '--title',
    `Release ${version}`,
    '--notes',
    `Draft notes for ${version}. Update before publishing.`
  ];
  const result = spawnSync('gh', args, { cwd: root, stdio: 'inherit', encoding: 'utf8' });
  if (result.status !== 0) {
    throw new Error('Failed to create draft release via gh.');
  }
}

async function main() {
  const [, , versionArg] = process.argv;
  if (!versionArg) {
    console.error('Usage: npm run release:finalize -- vX.Y.Z');
    process.exit(1);
    return;
  }
  const version = versionArg.trim();
  const branchName = `release/${version}`;
  const root = repoRoot();

  ensureCleanWorkingTree(root);
  ensureGhCli();

  fetchUpstream(root);

  if (!releaseBranchExists(root, branchName)) {
    throw new Error(`Branch ${branchName} not found. Ensure you created it with npm run release:branch.`);
  }

  // Checkout release branch and capture commit
  checkoutBranch(root, branchName);
  const releaseCommit = run('git', ['rev-parse', 'HEAD'], { cwd: root });

  // Fast-forward main with release branch
  mergeFastForward(root, 'main', branchName);
  const mainCommit = run('git', ['rev-parse', 'HEAD'], { cwd: root });

  // Create draft release
  createDraftRelease(root, version);

  // Fast-forward develop
  mergeFastForward(root, 'develop', branchName);
  const developCommit = run('git', ['rev-parse', 'HEAD'], { cwd: root });

  await writeFinalizeMetadata(root, version, {
    schema: 'release/finalize@v1',
    version,
    releaseBranch: branchName,
    releaseCommit,
    mainCommit,
    developCommit,
    createdDraftRelease: true,
    finalizedAt: new Date().toISOString()
  });

  console.log('[release:finalize] Release branch merged into main and develop. Draft release created.');
}

main().catch((error) => {
  console.error(`[release:finalize] ${error.message}`);
  process.exitCode = 1;
});
