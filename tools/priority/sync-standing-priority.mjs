#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import crypto from 'node:crypto';

function sh(cmd, args, opts = {}) {
  const res = spawnSync(cmd, args, { encoding: 'utf8', shell: false, ...opts });
  return res;
}

function gitRoot() {
  const r = sh('git', ['rev-parse', '--show-toplevel']);
  if (r.status !== 0) throw new Error('git rev-parse failed');
  return r.stdout.trim();
}

function readJson(file) {
  try {
    const s = fs.readFileSync(file, 'utf8');
    return JSON.parse(s);
  } catch (e) {
    return null;
  }
}

function writeJson(file, obj) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(obj, null, 2) + '\n', 'utf8');
}

function hashObject(obj) {
  const s = JSON.stringify(obj);
  return crypto.createHash('sha256').update(s).digest('hex');
}

function info(msg) { process.stdout.write(msg + '\n'); }
function warn(msg) { process.stderr.write(msg + '\n'); }

function resolveStandingPriorityNumber(repoRoot) {
  // Env override first
  const ov = process.env.AGENT_PRIORITY_OVERRIDE;
  if (ov) {
    try {
      if (ov.trim().startsWith('{')) {
        const o = JSON.parse(ov);
        if (o.number) return Number(o.number);
      } else {
        const n = ov.split('|')[0].trim();
        if (n) return Number(n);
      }
    } catch {}
  }
  // Try gh label query
  const ghPath = 'gh';
  try {
    const q = sh(ghPath, ['issue', 'list', '--label', 'standing-priority', '--state', 'open', '--limit', '1', '--json', 'number']);
    if (q.status === 0 && q.stdout.trim()) {
      const arr = JSON.parse(q.stdout);
      const first = Array.isArray(arr) ? arr[0] : arr;
      if (first && first.number) return Number(first.number);
    }
  } catch {}

  // Fallback to cache
  const cache = readJson(path.join(repoRoot, '.agent_priority_cache.json'));
  if (cache && typeof cache.number === 'number') return cache.number;
  throw new Error('Unable to resolve standing-priority issue number');
}

function fetchIssue(number) {
  const fields = ['number','title','state','updatedAt','url','labels','assignees','milestone','comments','body'];
  const args = ['api', `repos/${process.env.GITHUB_REPOSITORY || ''}/issues/${number}`, '--jq', `. | {number,title,state,updatedAt,html_url:.html_url,url:.url,labels,assignees,milestone,comments,body}`];
  // Prefer gh issue view if repository env not set
  let out = null;
  if (process.env.GITHUB_REPOSITORY) {
    const r = sh('gh', args);
    if (r.status === 0 && r.stdout.trim()) out = JSON.parse(r.stdout);
  }
  if (!out) {
    const r2 = sh('gh', ['issue', 'view', String(number), '--json', fields.join(',')]);
    if (r2.status === 0 && r2.stdout.trim()) out = JSON.parse(r2.stdout);
  }
  if (!out) throw new Error(`Failed to fetch issue #${number} via gh CLI`);
  // Normalize fields
  const labels = (out.labels || []).map(l => l.name || l).filter(Boolean).sort((a,b)=>a.localeCompare(b));
  const assignees = (out.assignees || []).map(a => a.login || a).filter(Boolean).sort((a,b)=>a.localeCompare(b));
  const milestone = out.milestone ? (out.milestone.title || out.milestone) : null;
  const comments = Array.isArray(out.comments) ? out.comments : (typeof out.comments === 'number' ? out.comments : null);
  return {
    number: out.number,
    title: out.title || null,
    state: out.state || null,
    updatedAt: out.updatedAt || out.updated_at || null,
    url: out.html_url || out.url || null,
    labels,
    assignees,
    milestone,
    commentCount: typeof comments === 'number' ? comments : null,
    body: out.body || null,
  };
}

function buildRouter(issue) {
  const actions = [];
  const labels = new Set(issue.labels || []);
  // Always include sanity hooks
  actions.push({ key: 'hooks:pre-commit', priority: 10, scripts: ['npm run hooks:pre-commit'] });
  actions.push({ key: 'hooks:multi', priority: 11, scripts: ['npm run hooks:multi','npm run hooks:schema'] });
  if (labels.has('docs') || labels.has('documentation')) {
    actions.push({ key: 'docs:lint', priority: 20, scripts: ['npm run lint:md:changed'], rationale: 'docs label present' });
  }
  if (labels.has('ci')) {
    actions.push({ key: 'ci:parity', priority: 30, scripts: ['npm run hooks:multi'], rationale: 'ci label present' });
  }
  if (labels.has('release')) {
    actions.push({ key: 'release:prep', priority: 40, scripts: ['pwsh -File tools/Branch-Orchestrator.ps1 -DryRun'], rationale: 'release label present' });
  }
  // Default suggested action
  if (actions.length < 3) {
    actions.push({ key: 'validate:lint', priority: 90, scripts: ['pwsh -File tools/PrePush-Checks.ps1'], rationale: 'baseline validation' });
  }
  // normalize priority ordering
  actions.sort((a,b)=>a.priority-b.priority || a.key.localeCompare(b.key));
  return { schema: 'agent/priority-router@v1', issue: issue.number, updatedAt: issue.updatedAt, actions };
}

function stepSummaryAppend(lines) {
  const f = process.env.GITHUB_STEP_SUMMARY;
  if (!f) return;
  fs.appendFileSync(f, lines.join('\n') + '\n');
}

function main() {
  const repoRoot = gitRoot();
  const cachePath = path.join(repoRoot, '.agent_priority_cache.json');
  const cache = readJson(cachePath) || {};
  const resultsDir = path.join(repoRoot, 'tests', 'results', '_agent');
  fs.mkdirSync(resultsDir, { recursive: true });

  const number = resolveStandingPriorityNumber(repoRoot);
  info(`[priority] Standing issue: #${number}`);
  let issue = null;
  let fetchError = null;
  try { issue = fetchIssue(number); } catch (e) { fetchError = e; }
  if (!issue) {
    warn(`[priority] Fetch failed: ${fetchError?.message || 'unknown'} — falling back to cache`);
    if (!cache || cache.number !== number) {
      throw new Error('No cached issue available to fall back to');
    }
    issue = { number: cache.number, title: cache.title, url: cache.url, state: cache.state || 'unknown', labels: [], assignees: [], milestone: null, commentCount: null, body: null, updatedAt: cache.lastSeenUpdatedAt || null };
  }

  // Build normalized snapshot (omit body for digest input to avoid noise, but include bodyDigest)
  const digestInput = { number: issue.number, title: issue.title, state: issue.state, updatedAt: issue.updatedAt, labels: issue.labels, assignees: issue.assignees, milestone: issue.milestone, commentCount: issue.commentCount };
  const digest = hashObject(digestInput);
  const bodyDigest = issue.body ? crypto.createHash('sha256').update(issue.body).digest('hex') : null;

  const snapshot = { ...issue, body: undefined, bodyDigest, digest, schema: 'standing-priority/issue@v1' };
  const outDir = path.join(resultsDir, 'issue');
  const snapPath = path.join(outDir, `${number}.json`);
  const digestPath = path.join(outDir, `${number}.digest`);
  writeJson(snapPath, snapshot);
  fs.writeFileSync(digestPath, digest + '\n', 'utf8');

  // Router
  const router = buildRouter(issue);
  writeJson(path.join(resultsDir, 'issue', 'router.json'), router);

  // Update cache if changed
  const newCache = { ...cache };
  newCache.number = number;
  newCache.title = issue.title || cache.title;
  newCache.url = issue.url || cache.url;
  newCache.lastSeenUpdatedAt = issue.updatedAt || null;
  newCache.issueDigest = digest;
  writeJson(cachePath, newCache);

  // Step summary
  const lines = [
    '### Standing Priority Snapshot',
    `- Issue: #${number} — ${issue.title || '(no title)'}`,
    `- State: ${issue.state}  Updated: ${issue.updatedAt || 'n/a'}`,
    `- Digest: \\`${digest}\\``,
    `- Labels: ${(issue.labels || []).join(', ') || 'none'}`,
    `- Router actions: ${router.actions.length}`,
  ];
  stepSummaryAppend(lines);
}

try {
  main();
  process.exit(0);
} catch (e) {
  warn('[priority] ' + e.message);
  process.exit(1);
}

