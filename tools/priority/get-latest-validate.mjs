#!/usr/bin/env node

import process from 'node:process';
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { run, getRepoRoot, getCurrentBranch } from './lib/branch-utils.mjs';
import { resolveRepoContext } from './lib/git-context.mjs';
import { ensureGhCli } from './lib/remote-utils.mjs';

const USAGE = [
  'Usage: node tools/priority/get-latest-validate.mjs [--branch <name>] [--limit <n>] [--json]',
  '',
  'Fetch metadata for the most recent Validate workflow runs associated with the given branch.',
  'Defaults to the current git branch when --branch is omitted.',
  '',
  'Options:',
  '  --branch <name>   Branch to inspect (defaults to current branch)',
  '  --limit <n>       Number of runs to return (default: 1)',
  '  --json            Emit the raw JSON payload returned by gh',
  '  --help, -h        Show this help message'
];

function printUsage() {
  for (const line of USAGE) {
    console.log(line);
  }
}

function parseCliOptions(argv = process.argv) {
  const args = Array.isArray(argv) ? argv.slice(2) : [];
  let branch = null;
  let limit = 1;
  let asJson = false;
  let help = false;

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    if (arg === '--help' || arg === '-h') {
      help = true;
      continue;
    }
    if (arg === '--branch') {
      if (i + 1 >= args.length) {
        throw new Error('--branch requires a value');
      }
      branch = args[i + 1];
      i += 1;
      continue;
    }
    if (arg === '--limit') {
      if (i + 1 >= args.length) {
        throw new Error('--limit requires a value');
      }
      const value = Number.parseInt(args[i + 1], 10);
      if (Number.isNaN(value) || value <= 0) {
        throw new Error('--limit must be a positive integer');
      }
      limit = value;
      i += 1;
      continue;
    }
    if (arg === '--json') {
      asJson = true;
      continue;
    }
    throw new Error(`Unknown option: ${arg}`);
  }

  return { branch, limit, asJson, help };
}

function formatRun(run) {
  if (!run) {
    return '  (no runs found)';
  }
  const parts = [
    `  Run ID      : ${run.databaseId ?? 'unknown'}`,
    `  Status      : ${run.status ?? 'unknown'} (${run.conclusion ?? 'pending'})`,
    `  Created At  : ${run.createdAt ?? 'n/a'}`,
    `  Updated At  : ${run.updatedAt ?? 'n/a'}`,
    `  Head SHA    : ${run.headSha ?? 'n/a'}`,
    `  Title       : ${run.displayTitle ?? run.name ?? 'Validate'}`,
    `  URL         : ${run.url ?? 'n/a'}`
  ];
  return parts.join('\n');
}

export function getLatestValidateRuns({
  branch,
  limit = 1,
  repoRoot = getRepoRoot(),
  ensureGhCliFn = ensureGhCli,
  runFn = run,
  resolveContextFn = resolveRepoContext,
  getCurrentBranchFn = getCurrentBranch
} = {}) {
  if (!branch) {
    branch = getCurrentBranchFn();
  }

  ensureGhCliFn();

  const context = resolveContextFn(repoRoot);
  if (!context?.upstream?.owner || !context?.upstream?.repo) {
    throw new Error('Unable to resolve upstream repository from git remotes.');
  }

  const slug = `${context.upstream.owner}/${context.upstream.repo}`;
  const ghArgs = [
    'run',
    'list',
    '--repo',
    slug,
    '--workflow',
    'Validate',
    '--branch',
    branch,
    '--json',
    'databaseId,status,conclusion,createdAt,updatedAt,headSha,url,displayTitle,name',
    '-L',
    String(limit)
  ];

  const output = runFn('gh', ghArgs, { cwd: repoRoot });
  let runs = [];
  if (output) {
    try {
      const parsed = JSON.parse(output);
      if (Array.isArray(parsed)) {
        runs = parsed;
      }
    } catch (err) {
      throw new Error(`Unable to parse gh response: ${err.message}`);
    }
  }

  return {
    repo: slug,
    branch,
    runs
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const options = parseCliOptions(process.argv);
    if (options.help) {
      printUsage();
      process.exit(0);
    }

    const repoRoot = getRepoRoot();
    const result = getLatestValidateRuns({
      branch: options.branch,
      limit: options.limit,
      repoRoot
    });

    if (options.asJson) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      console.log(`Repository : ${result.repo}`);
      console.log(`Branch     : ${result.branch}`);
      console.log(`Returned   : ${result.runs.length} run(s)\n`);
      if (result.runs.length === 0) {
        console.log('  No Validate runs found for this branch.');
      } else {
        result.runs.forEach((runInfo, index) => {
          console.log(`Run #${index + 1}`);
          console.log(formatRun(runInfo));
          console.log('');
        });
      }

      const agentFile = path.join(repoRoot, 'tests', 'results', '_agent', 'validate-latest.json');
      if (fs.existsSync(agentFile)) {
        try {
          const cached = JSON.parse(fs.readFileSync(agentFile, 'utf8'));
          console.log('Local cache:');
          console.log(`  File       : ${agentFile}`);
          console.log(`  Repository : ${cached.repo}`);
          console.log(`  Ref        : ${cached.ref}`);
          console.log(`  Dispatched : ${cached.dispatchedAt}`);
          if (cached.run?.id) {
            console.log(`  Run ID     : ${cached.run.id}`);
            console.log(`  Status     : ${cached.run.status ?? 'unknown'} (${cached.run.conclusion ?? 'pending'})`);
          }
        } catch (err) {
          console.warn(`[validate] Warning: unable to read ${agentFile}: ${err.message}`);
        }
      }
    }
  } catch (err) {
    console.error(`[validate] ${err.message}`);
    process.exit(1);
  }
}
