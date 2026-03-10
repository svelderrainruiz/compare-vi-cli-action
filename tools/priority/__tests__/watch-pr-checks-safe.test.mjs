#!/usr/bin/env node

import test from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const watcherPath = path.join(repoRoot, 'tools', 'Watch-PRChecksSafe.ps1');

function writeGhShim(tempDir, mode) {
  const statePath = path.join(tempDir, 'state.json');
  const shimPath = path.join(tempDir, 'gh-shim.mjs');
  writeFileSync(statePath, JSON.stringify({ mode, checksCalls: 0, jobApiCalls: 0 }, null, 2), 'utf8');
  writeFileSync(
    shimPath,
    `#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const statePath = path.join(${JSON.stringify(tempDir)}, 'state.json');
const state = JSON.parse(readFileSync(statePath, 'utf8'));
const args = process.argv.slice(2);

function persist() {
  writeFileSync(statePath, JSON.stringify(state, null, 2));
}

if (args[0] === 'pr' && args[1] === 'checks') {
  state.checksCalls += 1;
  persist();

  if (state.mode === 'transient-no-checks') {
    if (state.checksCalls === 1) {
      process.stderr.write("no checks reported on the 'test-branch' branch\\n");
      process.exit(1);
    }
    if (state.checksCalls === 2) {
      process.stdout.write(JSON.stringify([{ workflow: 'Validate', name: 'lint', bucket: 'pending', state: 'IN_PROGRESS', link: 'https://example.invalid/check/1' }]));
      process.exit(0);
    }
    process.stdout.write(JSON.stringify([{ workflow: 'Validate', name: 'lint', bucket: 'pass', state: 'COMPLETED', link: 'https://example.invalid/check/1' }]));
    process.exit(0);
  }

  if (state.mode === 'self-hosted-starvation') {
    process.stdout.write(JSON.stringify([{
      workflow: 'Validate',
      name: 'fixtures',
      bucket: 'pending',
      state: 'QUEUED',
      link: 'https://github.com/example/repo/actions/runs/123/job/777'
    }]));
    process.exit(0);
  }

  process.stderr.write("no checks reported on the 'test-branch' branch\\n");
  process.exit(1);
}

if (args[0] === 'api' && args[1] === 'repos/example/repo/actions/jobs/777') {
  state.jobApiCalls += 1;
  persist();
  process.stdout.write(JSON.stringify({
    id: 777,
    run_id: 123,
    workflow_name: 'Validate',
    status: 'queued',
    created_at: '2020-01-01T00:00:00Z',
    started_at: '2020-01-01T00:00:00Z',
    labels: ['self-hosted', 'Windows', 'X64'],
    runner_id: 0,
    runner_name: '',
    runner_group_id: 0,
    runner_group_name: ''
  }));
  process.exit(0);
}

process.stderr.write(\`unexpected gh invocation: \${args.join(' ')}\\n\`);
process.exit(1);
`,
    'utf8'
  );

  const launcherPosix = path.join(tempDir, 'gh');
  writeFileSync(
    launcherPosix,
    `#!/usr/bin/env bash
"${process.execPath.replace(/\\/g, '/')}" "$(dirname "$0")/gh-shim.mjs" "$@"
`,
    'utf8'
  );
  chmodSync(launcherPosix, 0o755);

  const launcherWindows = path.join(tempDir, 'gh.cmd');
  writeFileSync(
    launcherWindows,
    `@echo off\r\n"${process.execPath}" "%~dp0gh-shim.mjs" %*\r\n`,
    'utf8'
  );

  return statePath;
}

function runWatcherScenario(mode, maxPolls, extraArgs = []) {
  const tempDir = mkdtempSync(path.join(os.tmpdir(), 'watch-pr-checks-safe-'));
  const statePath = writeGhShim(tempDir, mode);
  const env = {
    ...process.env,
    PATH: `${tempDir}${path.delimiter}${process.env.PATH ?? ''}`,
    WATCH_PR_CHECKS_POLL_DELAY_MILLISECONDS: '1'
  };

  try {
    const result = spawnSync(
      'pwsh',
      [
        '-NoLogo',
        '-NoProfile',
        '-File',
        watcherPath,
        '-PullRequest',
        '5',
        '-Repository',
        'example/repo',
        '-IntervalSeconds',
        '5',
        '-HeartbeatPolls',
        '1',
        '-MaxPolls',
        String(maxPolls),
        '-RequiredOnly',
        ...extraArgs
      ],
      {
        cwd: repoRoot,
        env,
        encoding: 'utf8'
      }
    );

    return {
      result,
      state: JSON.parse(readFileSync(statePath, 'utf8'))
    };
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
}

test('Watch-PRChecksSafe tolerates a transient no-check state before checks appear', () => {
  const { result, state } = runWatcherScenario('transient-no-checks', 4);

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(state.checksCalls, 3);
  assert.match(result.stdout, /checks=none-yet/);
  assert.match(result.stdout, /All tracked checks completed successfully\./);
});

test('Watch-PRChecksSafe does not false-pass when no checks ever appear', () => {
  const { result, state } = runWatcherScenario('persistent-no-checks', 2);

  assert.equal(result.status, 8, result.stderr || result.stdout);
  assert.equal(state.checksCalls, 2);
  assert.match(result.stdout, /Reached MaxPolls=2 with no checks reported yet\./);
});

test('Watch-PRChecksSafe classifies aged queued self-hosted jobs without runner assignment as a blocker', () => {
  const { result, state } = runWatcherScenario('self-hosted-starvation', 2, [
    '-RunnerAdmissionQueueThresholdMinutes',
    '1'
  ]);

  assert.equal(result.status, 9, result.stderr || result.stdout);
  assert.equal(state.checksCalls, 1);
  assert.equal(state.jobApiCalls, 1);
  assert.match(result.stdout, /self-hosted runner admission starvation detected/);
  assert.match(result.stdout, /Validate\/fixtures: queued=/);
});
