#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import yaml from 'js-yaml';
import { runForkLaneDesignAudit } from './fork-lane-design-audit.mjs';

const repoRootDefault = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const defaultSkillRoot = path.join(process.env.HOME ?? '', '.codex', 'skills', 'repo-standards-review');
const fallbackSkillRoot = '/mnt/c/Users/sveld/.codex/skills/repo-standards-review';

const DEFAULT_SURFACE = path.join('tools', 'priority', 'fork-lanes', 'audit-surface.yaml');
const DEFAULT_RESULTS_DIR = path.join('tests', 'results', '_agent', 'fork-lanes', 'local-assurance');
const DEFAULT_REPORT = path.join(DEFAULT_RESULTS_DIR, 'fork-lane-assurance-report.json');
const DEFAULT_SUMMARY = path.join(DEFAULT_RESULTS_DIR, 'fork-lane-assurance-summary.md');

const HELP = [
  'Usage: node tools/priority/fork-lane-local-assurance-ci.mjs [options]',
  '',
  'Options:',
  `  --repo-root <path>      (default: ${repoRootDefault})`,
  `  --skill-root <path>     (default: ${defaultSkillRoot} or ${fallbackSkillRoot})`,
  `  --surface <path>        (default: ${DEFAULT_SURFACE})`,
  `  --results-dir <path>    (default: ${DEFAULT_RESULTS_DIR})`,
  `  --output <path>         (default: ${DEFAULT_REPORT})`,
  `  --summary-output <path> (default: ${DEFAULT_SUMMARY})`,
  '  --help, -h'
];

function parseArgs(argv = process.argv) {
  const options = {
    repoRoot: repoRootDefault,
    skillRoot: null,
    surfacePath: DEFAULT_SURFACE,
    resultsDir: DEFAULT_RESULTS_DIR,
    outputPath: DEFAULT_REPORT,
    summaryPath: DEFAULT_SUMMARY,
    help: false
  };

  const args = argv.slice(2);
  for (let i = 0; i < args.length; i += 1) {
    const token = args[i];
    const next = args[i + 1];
    if (token === '--help' || token === '-h') {
      options.help = true;
      continue;
    }
    if (['--repo-root', '--skill-root', '--surface', '--results-dir', '--output', '--summary-output'].includes(token)) {
      if (!next || next.startsWith('-')) throw new Error(`Missing value for ${token}`);
      i += 1;
      if (token === '--repo-root') options.repoRoot = path.resolve(next);
      if (token === '--skill-root') options.skillRoot = path.resolve(next);
      if (token === '--surface') options.surfacePath = next;
      if (token === '--results-dir') options.resultsDir = next;
      if (token === '--output') options.outputPath = next;
      if (token === '--summary-output') options.summaryPath = next;
      continue;
    }
    throw new Error(`Unknown option: ${token}`);
  }
  return options;
}

function printHelp() {
  for (const line of HELP) console.log(line);
}

async function readYaml(filePath) {
  return yaml.load(await fs.readFile(filePath, 'utf8'));
}

async function ensureDir(filePath) {
  await fs.mkdir(filePath, { recursive: true });
}

async function fileExists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function resolveSkillRoot(explicitRoot) {
  if (explicitRoot) return explicitRoot;
  const candidates = [];
  if (process.env.CODEX_HOME) candidates.push(path.join(process.env.CODEX_HOME, 'skills', 'repo-standards-review'));
  candidates.push(defaultSkillRoot, fallbackSkillRoot);
  for (const candidate of candidates) {
    if (await fileExists(candidate)) return candidate;
  }
  return defaultSkillRoot;
}

function relativeFrom(repoRoot, filePath) {
  return path.relative(repoRoot, filePath).split(path.sep).join('/');
}

async function materializeAuditSurface(repoRoot, manifest, bundleRoot) {
  await fs.rm(bundleRoot, { recursive: true, force: true });
  await ensureDir(bundleRoot);
  for (const relativePath of manifest.include) {
    const source = path.join(repoRoot, relativePath);
    const destination = path.join(bundleRoot, relativePath);
    await ensureDir(path.dirname(destination));
    await fs.copyFile(source, destination);
  }
}

function runCommand(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd,
    encoding: 'utf8',
    maxBuffer: 20 * 1024 * 1024
  });
  if (result.status !== 0) {
    throw new Error([`${command} ${args.join(' ')}`, result.stdout?.trim(), result.stderr?.trim()].filter(Boolean).join('\n'));
  }
  return result;
}

function deriveStandardsActionItems(score) {
  const areaOrder = ['REQ', 'ARCH', 'TEST', 'CM', 'DOC'];
  const items = [];
  for (const area of areaOrder) {
    const details = score.areas?.[area];
    if (!details) continue;
    if (details.score >= 3) continue;
    items.push({
      id: `standards-${area.toLowerCase()}-uplift`,
      source: 'standards-audit',
      priority: details.score <= 1 ? 'high' : 'medium',
      title: `Raise ${area} assurance on the fork-lane control plane`,
      description: `${details.rationale} Next fix: ${details.top_fix}`,
      standards: details.standards ?? [],
      evidence_paths: details.evidence_paths ?? []
    });
  }
  return items;
}

function buildSummary(report, score) {
  const lines = [
    '# Fork Lane Local Assurance',
    '',
    `- Overall: ${report.overall.status}`,
    `- Design audit: ${report.design_audit.status}`,
    `- Standards audit: ${report.standards_audit.status}`,
    `- Action items: ${report.action_items.length}`,
    '',
    '## Standards Areas',
    ''
  ];

  for (const [area, details] of Object.entries(score.areas ?? {})) {
    lines.push(`- ${area}: score=${details.score} rating=${details.rating} confidence=${details.confidence}`);
    lines.push(`  top-fix: ${details.top_fix}`);
  }

  if (report.action_items.length > 0) {
    lines.push('', '## Action Items', '');
    for (const item of report.action_items) {
      lines.push(`- [${item.priority}] ${item.title}`);
      lines.push(`  source: ${item.source}`);
      lines.push(`  ${item.description}`);
    }
  }

  return lines.join('\n') + '\n';
}

export { deriveStandardsActionItems };

export async function runForkLaneLocalAssurance({
  repoRoot = repoRootDefault,
  skillRoot = null,
  surfacePath = DEFAULT_SURFACE,
  resultsDir = DEFAULT_RESULTS_DIR,
  outputPath = DEFAULT_REPORT,
  summaryPath = DEFAULT_SUMMARY
} = {}) {
  const resolvedSkillRoot = await resolveSkillRoot(skillRoot);
  const resolved = {
    repoRoot,
    skillRoot: resolvedSkillRoot,
    surfacePath: path.join(repoRoot, surfacePath),
    resultsDir: path.join(repoRoot, resultsDir),
    outputPath: path.join(repoRoot, outputPath),
    summaryPath: path.join(repoRoot, summaryPath)
  };

  const manifest = await readYaml(resolved.surfacePath);
  const bundleRoot = path.join(resolved.resultsDir, 'surface-bundle');
  await ensureDir(resolved.resultsDir);
  await materializeAuditSurface(repoRoot, manifest, bundleRoot);

  const designReportPath = path.join(resultsDir, 'fork-lane-design-audit-report.json');
  const designSummaryPath = path.join(resultsDir, 'fork-lane-design-audit-summary.md');
  const { report: designReport } = await runForkLaneDesignAudit({
    repoRoot,
    outputPath: designReportPath,
    summaryPath: designSummaryPath
  });

  const evidencePath = path.join(resolved.resultsDir, 'standards-evidence.json');
  const scorePath = path.join(resolved.resultsDir, 'standards-score.json');

  const evidence = runCommand('python3', [
    path.join(resolvedSkillRoot, 'scripts', 'repo_evidence_scan.py'),
    bundleRoot,
    '--format',
    'json',
    '--profile',
    'quick-triage',
    '--max-examples',
    '2',
    '--max-evidence-per-rule',
    '2'
  ], { cwd: repoRoot }).stdout;
  await fs.writeFile(evidencePath, evidence, 'utf8');

  const score = runCommand('python3', [
    path.join(resolvedSkillRoot, 'scripts', 'score_assurance.py'),
    evidencePath,
    '--format',
    'json'
  ], { cwd: repoRoot }).stdout;
  await fs.writeFile(scorePath, score, 'utf8');

  const scorePayload = JSON.parse(score);
  const standardsActionItems = deriveStandardsActionItems(scorePayload);
  const designActionItems = (designReport.actionItems ?? []).map((item) => ({
    id: item.id,
    source: 'design-audit',
    priority: item.priority,
    title: item.title,
    description: item.description,
    standards: item.standards ?? [],
    evidence_paths: []
  }));

  const actionItems = [...designActionItems, ...standardsActionItems];
  const overallStatus = actionItems.length === 0 ? 'pass' : 'pass-with-actions';

  const report = {
    schema_version: '1.0.0',
    generated_at: new Date().toISOString(),
    repo_root: repoRoot,
    audit_surface: {
      id: manifest.id,
      description: manifest.description,
      manifest_path: relativeFrom(repoRoot, resolved.surfacePath),
      bundle_root: relativeFrom(repoRoot, bundleRoot),
      included_paths: manifest.include
    },
    design_audit: {
      status: designReport.overall.status,
      report_path: designReportPath,
      summary_path: designSummaryPath,
      finding_count: designReport.findings.length,
      action_item_count: designReport.actionItems.length
    },
    standards_audit: {
      status: standardsActionItems.length === 0 ? 'pass' : 'pass-with-actions',
      profile: 'quick-triage',
      evidence_path: relativeFrom(repoRoot, evidencePath),
      score_path: relativeFrom(repoRoot, scorePath),
      top_risk_count: (scorePayload.top_risks ?? []).length,
      derived_action_item_count: standardsActionItems.length
    },
    overall: {
      status: overallStatus,
      action_item_count: actionItems.length
    },
    action_items: actionItems
  };

  const summary = buildSummary(report, scorePayload);
  await ensureDir(path.dirname(resolved.outputPath));
  await fs.writeFile(resolved.outputPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  await ensureDir(path.dirname(resolved.summaryPath));
  await fs.writeFile(resolved.summaryPath, summary, 'utf8');

  return { report, score: scorePayload };
}

async function main() {
  let options;
  try {
    options = parseArgs();
  } catch (error) {
    console.error(error.message);
    printHelp();
    process.exit(1);
  }

  if (options.help) {
    printHelp();
    return;
  }

  const skillRoot = await resolveSkillRoot(options.skillRoot);
  if (!(await fileExists(skillRoot))) {
    throw new Error(`Skill root not found: ${skillRoot}`);
  }

  const { report } = await runForkLaneLocalAssurance({
    repoRoot: options.repoRoot,
    skillRoot,
    surfacePath: options.surfacePath,
    resultsDir: options.resultsDir,
    outputPath: options.outputPath,
    summaryPath: options.summaryPath
  });

  console.log(`status=${report.overall.status}`);
  console.log(`action_items=${report.overall.action_item_count}`);
}

const isEntrypoint = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isEntrypoint) {
  main().catch((error) => {
    console.error(error.stack || error.message);
    process.exit(1);
  });
}
