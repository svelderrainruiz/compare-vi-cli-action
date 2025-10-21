#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import { access } from 'node:fs/promises';
import { execSync } from 'node:child_process';
import process from 'node:process';

const manifestPath = new URL('./policy.json', import.meta.url);

async function loadManifest() {
  const raw = await readFile(manifestPath, 'utf8');
  return JSON.parse(raw);
}

function parseRemoteUrl(url) {
  if (!url) return null;
  const sshMatch = url.match(/:(?<repoPath>[^/]+\/[^/]+)(?:\.git)?$/);
  const httpsMatch = url.match(/github\.com\/(?<repoPath>[^/]+\/[^/]+)(?:\.git)?$/);
  const repoPath = sshMatch?.groups?.repoPath ?? httpsMatch?.groups?.repoPath;
  if (!repoPath) return null;
  const [owner, repoRaw] = repoPath.split('/');
  if (!owner || !repoRaw) {
    return null;
  }
  const repo = repoRaw.endsWith('.git') ? repoRaw.slice(0, -4) : repoRaw;
  return { owner, repo };
}

function getRepoFromEnv() {
  const envRepo = process.env.GITHUB_REPOSITORY;
  if (envRepo && envRepo.includes('/')) {
    const [owner, repo] = envRepo.split('/');
    return { owner, repo };
  }

  try {
    const remoteNames = ['upstream', 'origin'];
    for (const remoteName of remoteNames) {
      try {
        const url = execSync(`git config --get remote.${remoteName}.url`, {
          stdio: ['ignore', 'pipe', 'ignore']
        })
          .toString()
          .trim();
        const parsed = parseRemoteUrl(url);
        if (parsed) {
          return parsed;
        }
      } catch {
        // ignore missing remote
      }
    }
  } catch (error) {
    throw new Error(`Failed to determine repository. Hint: set GITHUB_REPOSITORY. ${error.message}`);
  }

  throw new Error('Unable to determine repository owner/name. Set GITHUB_REPOSITORY or define an upstream remote.');
}

async function resolveToken() {
  const envToken =
    process.env.GITHUB_TOKEN ?? process.env.GH_TOKEN ?? process.env.GH_ENTERPRISE_TOKEN;
  if (envToken && envToken.trim()) {
    return envToken.trim();
  }

  const candidates = [process.env.GH_TOKEN_FILE];
  if (process.platform === 'win32') {
    candidates.push('C:\\github_token.txt');
  }

  for (const candidate of candidates) {
    if (!candidate) {
      continue;
    }
    try {
      await access(candidate);
      const fileToken = (await readFile(candidate, 'utf8')).trim();
      if (fileToken) {
        return fileToken;
      }
    } catch {
      // ignore missing/invalid file
    }
  }

  return null;
}

async function fetchJson(url, token) {
  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${token}`,
      'User-Agent': 'priority-policy-check',
      Accept: 'application/vnd.github+json'
    }
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`GitHub API request failed: ${response.status} ${response.statusText} -> ${text}`);
  }

  return response.json();
}

function compareRepoSettings(expected, actual) {
  const diffs = [];
  for (const [key, value] of Object.entries(expected)) {
    if (actual[key] !== value) {
      diffs.push(`repo.${key}: expected ${value}, actual ${actual[key]}`);
    }
  }
  return diffs;
}

function compareBranchSettings(branch, expected, actualProtection) {
  if (!actualProtection) {
    return [`branch ${branch}: protection settings not found`];
  }

  const diffs = [];

  if (expected.required_linear_history !== undefined) {
    const actualLinear = actualProtection.required_linear_history?.enabled ?? false;
    if (actualLinear !== expected.required_linear_history) {
      diffs.push(
        `branch ${branch}: required_linear_history expected ${expected.required_linear_history}, actual ${actualLinear}`
      );
    }
  }

  if (Array.isArray(expected.required_status_checks)) {
    const actualChecks =
      actualProtection.required_status_checks?.checks?.map((check) => check.context).filter(Boolean) ?? [];
    const normalizedExpected = [...new Set(expected.required_status_checks)].sort();
    const normalizedActual = [...new Set(actualChecks)].sort();

    const missing = normalizedExpected.filter((context) => !normalizedActual.includes(context));
    const extra = normalizedActual.filter((context) => !normalizedExpected.includes(context));

    if (missing.length > 0 || extra.length > 0) {
      const parts = [];
      if (missing.length > 0) {
        parts.push(`missing [${missing.join(', ')}]`);
      }
      if (extra.length > 0) {
        parts.push(`unexpected [${extra.join(', ')}]`);
      }
      diffs.push(`branch ${branch}: required_status_checks mismatch (${parts.join('; ')})`);
    }
  }

  return diffs;
}

const branchCache = {
  all: null
};

async function fetchAllBranches(repoUrl, token) {
  if (branchCache.all) {
    return branchCache.all;
  }

  const branches = [];
  let page = 1;
  while (true) {
    const url = `${repoUrl}/branches?per_page=100&page=${page}`;
    const data = await fetchJson(url, token);
    if (!Array.isArray(data) || data.length === 0) {
      break;
    }
    branches.push(...data);
    if (data.length < 100) {
      break;
    }
    page += 1;
  }

  branchCache.all = branches;
  return branches;
}

async function main() {
  const manifest = await loadManifest();
  const token = await resolveToken();
  if (!token) {
    throw new Error('GitHub token not found. Set GITHUB_TOKEN, GH_TOKEN, or GH_TOKEN_FILE.');
  }
  const { owner, repo } = getRepoFromEnv();

  const repoUrl = `https://api.github.com/repos/${owner}/${repo}`;
  const repoData = await fetchJson(repoUrl, token);

  const repoDiffs = compareRepoSettings(manifest.repo ?? {}, repoData);

  const branchDiffs = [];
  const manifestBranches = manifest.branches ?? {};
  const wildcardEntries = Object.entries(manifestBranches).filter(([branch]) => branch.includes('*'));
  const regularEntries = Object.entries(manifestBranches).filter(([branch]) => !branch.includes('*'));

  for (const [branch, expectations] of regularEntries) {
    try {
      const protectionUrl = `${repoUrl}/branches/${encodeURIComponent(branch)}/protection`;
      const protection = await fetchJson(protectionUrl, token);
      branchDiffs.push(...compareBranchSettings(branch, expectations, protection));
    } catch (error) {
      branchDiffs.push(`branch ${branch}: failed to load protection -> ${error.message}`);
    }
  }

  if (wildcardEntries.length > 0) {
    const allBranches = await fetchAllBranches(repoUrl, token);
    for (const [pattern, expectations] of wildcardEntries) {
      const prefix = pattern.replace('*', '');
      const matches = allBranches.filter((branch) => branch.name.startsWith(prefix));
      if (matches.length === 0) {
        continue;
      }
      for (const match of matches) {
        const branchProtected = match.protected && match.protection?.enabled !== false;
        let committedDate = null;
        try {
          const commitData = await fetchJson(match.commit.url, token);
          committedDate = commitData.commit?.committer?.date ?? commitData.commit?.author?.date ?? null;
        } catch (error) {
          branchDiffs.push(`branch ${match.name}: failed to read commit date -> ${error.message}`);
        }

        const maxAgeMs = expectations.stale_days ? expectations.stale_days * 24 * 60 * 60 * 1000 : null;
        let isStale = false;
        if (maxAgeMs && committedDate) {
          const ageMs = Date.now() - new Date(committedDate).getTime();
          if (ageMs > maxAgeMs) {
            isStale = true;
            const ageDays = Math.floor(ageMs / (24 * 60 * 60 * 1000));
            branchDiffs.push(
              `branch ${match.name}: stale (${ageDays} days since last commit, threshold ${expectations.stale_days} days)`
            );
          }
        }

        if (!branchProtected) {
          if (!isStale) {
            branchDiffs.push(`branch ${match.name}: expected protection but branch is not protected`);
          }
          continue;
        }

        try {
          const protectionUrl = `${repoUrl}/branches/${encodeURIComponent(match.name)}/protection`;
          const protection = await fetchJson(protectionUrl, token);
          branchDiffs.push(...compareBranchSettings(match.name, expectations, protection));
        } catch (error) {
          if (isStale && error.message.includes('404')) {
            continue;
          }
          branchDiffs.push(`branch ${match.name}: failed to load protection -> ${error.message}`);
        }
      }
    }
  }

  const diffs = [...repoDiffs, ...branchDiffs];

  if (diffs.length > 0) {
    console.error('Merge policy mismatches detected:');
    for (const diff of diffs) {
      console.error(` - ${diff}`);
    }
    process.exitCode = 1;
  } else {
    console.log('Merge policy check passed.');
  }
}

main().catch((error) => {
  console.error(`Policy check failed: ${error.stack ?? error.message}`);
  process.exitCode = 1;
});
