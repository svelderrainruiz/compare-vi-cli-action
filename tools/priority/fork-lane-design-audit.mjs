#!/usr/bin/env node

import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import yaml from 'js-yaml';

const repoRootDefault = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const DEFAULT_INDEX = path.join('tools', 'priority', 'fork-lanes', 'index.yaml');
const DEFAULT_TEMPLATE = path.join('tools', 'priority', 'fork-lanes', 'template.yaml');
const DEFAULT_POLICY = path.join('tools', 'priority', 'fork-lanes', 'design-audit-policy.json');
const DEFAULT_OUTPUT = path.join('tests', 'results', '_agent', 'fork-lanes', 'fork-lane-design-audit-report.json');
const DEFAULT_SUMMARY = path.join('tests', 'results', '_agent', 'fork-lanes', 'fork-lane-design-audit-summary.md');

const HELP = [
  'Usage: node tools/priority/fork-lane-design-audit.mjs [options]',
  '',
  'Options:',
  `  --repo-root <path>      (default: ${repoRootDefault})`,
  `  --index <path>          (default: ${DEFAULT_INDEX})`,
  `  --template <path>       (default: ${DEFAULT_TEMPLATE})`,
  `  --policy <path>         (default: ${DEFAULT_POLICY})`,
  `  --output <path>         (default: ${DEFAULT_OUTPUT})`,
  `  --summary-output <path> (default: ${DEFAULT_SUMMARY})`,
  '  --help, -h'
];

function parseArgs(argv = process.argv) {
  const options = {
    repoRoot: repoRootDefault,
    indexPath: DEFAULT_INDEX,
    templatePath: DEFAULT_TEMPLATE,
    policyPath: DEFAULT_POLICY,
    outputPath: DEFAULT_OUTPUT,
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
    if (['--repo-root', '--index', '--template', '--policy', '--output', '--summary-output'].includes(token)) {
      if (!next || next.startsWith('-')) {
        throw new Error(`Missing value for ${token}`);
      }
      i += 1;
      if (token === '--repo-root') options.repoRoot = path.resolve(next);
      if (token === '--index') options.indexPath = next;
      if (token === '--template') options.templatePath = next;
      if (token === '--policy') options.policyPath = next;
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

async function readJson(filePath) {
  return JSON.parse(await fs.readFile(filePath, 'utf8'));
}

async function fileExists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

function relativeFrom(repoRoot, filePath) {
  return path.relative(repoRoot, filePath).split(path.sep).join('/');
}

function lineOf(sourceText, needle) {
  const index = sourceText.indexOf(needle);
  if (index === -1) return null;
  return sourceText.slice(0, index).split('\n').length;
}

function unique(array) {
  return Array.from(new Set(array));
}

function compareArrays(left, right) {
  return JSON.stringify([...left].sort()) === JSON.stringify([...right].sort());
}

function buildActionItem(check, findingId, description) {
  return {
    id: check.actionItem.id,
    priority: check.actionItem.priority,
    title: check.actionItem.title,
    description,
    acceptance: check.actionItem.acceptance,
    standards: check.standards,
    relatedFindingIds: [findingId]
  };
}

export async function runForkLaneDesignAudit({
  repoRoot = repoRootDefault,
  indexPath = DEFAULT_INDEX,
  templatePath = DEFAULT_TEMPLATE,
  policyPath = DEFAULT_POLICY,
  outputPath = DEFAULT_OUTPUT,
  summaryPath = DEFAULT_SUMMARY
} = {}) {
  const resolved = {
    repoRoot,
    indexPath: path.join(repoRoot, indexPath),
    templatePath: path.join(repoRoot, templatePath),
    policyPath: path.join(repoRoot, policyPath),
    outputPath: path.join(repoRoot, outputPath),
    summaryPath: path.join(repoRoot, summaryPath)
  };

  const [index, template, policy, instanceSchemaText, instanceSchema, indexSchemaText, indexSchema] = await Promise.all([
    readYaml(resolved.indexPath),
    readYaml(resolved.templatePath),
    readJson(resolved.policyPath),
    fs.readFile(path.join(repoRoot, 'docs', 'schemas', 'fork-lane-instance-v1.schema.json'), 'utf8'),
    readJson(path.join(repoRoot, 'docs', 'schemas', 'fork-lane-instance-v1.schema.json')),
    fs.readFile(path.join(repoRoot, 'docs', 'schemas', 'fork-lane-index-v1.schema.json'), 'utf8'),
    readJson(path.join(repoRoot, 'docs', 'schemas', 'fork-lane-index-v1.schema.json'))
  ]);

  const instancePaths = index.instances.map((entry) => path.join(repoRoot, entry.path));
  const instanceDocs = await Promise.all(instancePaths.map((filePath) => readYaml(filePath)));
  const instanceTexts = await Promise.all(instancePaths.map((filePath) => fs.readFile(filePath, 'utf8')));

  const findings = [];
  const actionItems = [];

  const addFinding = ({ id, title, severity, summary, standards, evidence, actionItem }) => {
    findings.push({
      id,
      title,
      severity,
      status: 'finding',
      summary,
      standards,
      evidence,
      actionItemIds: actionItem ? [actionItem.id] : []
    });
    if (actionItem) actionItems.push(actionItem);
  };

  const addPass = ({ id, title, severity, summary, standards, evidence }) => {
    findings.push({
      id,
      title,
      severity,
      status: 'pass',
      summary,
      standards,
      evidence,
      actionItemIds: []
    });
  };

  const checks = new Map(policy.checks.map((check) => [check.id, check]));

  {
    const check = checks.get('index-reconciliation');
    const mismatches = [];
    for (let i = 0; i < index.instances.length; i += 1) {
      const entry = index.instances[i];
      const instance = instanceDocs[i];
      const selectedFork = instance.forks.catalog.find((fork) => fork.id === instance.forks.selected);
      if (!selectedFork) {
        mismatches.push(`selected fork '${instance.forks.selected}' missing in ${entry.path}`);
        continue;
      }
      if (entry.issue_number !== instance.issue.number) mismatches.push(`${entry.path}: issue number drift`);
      if (entry.title !== instance.issue.title) mismatches.push(`${entry.path}: title drift`);
      if (entry.status !== instance.lifecycle.status) mismatches.push(`${entry.path}: status drift`);
      if (entry.selected_fork_id !== instance.forks.selected) mismatches.push(`${entry.path}: selected fork drift`);
      if (!compareArrays(entry.fork_repositories, instance.forks.catalog.map((fork) => fork.repository))) mismatches.push(`${entry.path}: fork repository catalog drift`);
      if (entry.fork_branch !== selectedFork.branch) mismatches.push(`${entry.path}: selected fork branch drift`);
      if (entry.upstream_branch !== instance.upstream.integration_branch) mismatches.push(`${entry.path}: upstream branch drift`);
    }
    if (mismatches.length > 0) {
      addFinding({
        id: check.id,
        title: check.title,
        severity: check.severity,
        summary: mismatches.join('; '),
        standards: check.standards,
        evidence: [
          { path: relativeFrom(repoRoot, resolved.indexPath), detail: 'Active index is the configuration-status register for fork lane instances.' }
        ],
        actionItem: buildActionItem(check, check.id, 'Make the active fork-lane index a reconciled view of checked-in instance manifests.')
      });
    } else {
      addPass({
        id: check.id,
        title: check.title,
        severity: 'info',
        summary: 'The active index matches the checked-in instance manifest for the active issue.',
        standards: check.standards,
        evidence: [
          { path: relativeFrom(repoRoot, resolved.indexPath), detail: 'Active issue register matches the referenced issue manifest.' }
        ]
      });
    }
  }

  {
    const check = checks.get('proof-plane-separation');
    const instance = instanceDocs[0];
    if (instance.policy.fork_remote_proof === false && instance.policy.upstream_remote_proof === true) {
      addPass({
        id: check.id,
        title: check.title,
        severity: 'info',
        summary: 'Fork-local regression and upstream remote proof are explicitly separated in policy.',
        standards: check.standards,
        evidence: [
          {
            path: relativeFrom(repoRoot, instancePaths[0]),
            line: lineOf(instanceTexts[0], 'fork_remote_proof: false'),
            detail: 'Fork-side remote proof is disabled while upstream proof remains enabled.'
          }
        ]
      });
    } else {
      addFinding({
        id: check.id,
        title: check.title,
        severity: check.severity,
        summary: 'The instance policy does not explicitly separate fork-local regression from upstream remote proof.',
        standards: check.standards,
        evidence: [
          { path: relativeFrom(repoRoot, instancePaths[0]), detail: 'Proof-plane policy is not explicit.' }
        ],
        actionItem: buildActionItem(check, check.id, 'Separate fork-local regression policy from upstream remote proof policy in the instance manifest.')
      });
    }
  }

  {
    const check = checks.get('fork-capability-contract');
    const instance = instanceDocs[0];
    const schemaText = instanceSchemaText;
    const missingCapabilities = [];
    const requiredCapabilityKeys = ['push_enabled', 'mount_allowed'];
    for (const fork of instance.forks.catalog) {
      for (const key of requiredCapabilityKeys) {
        if (!(key in fork)) missingCapabilities.push(`${fork.id}.${key}`);
      }
    }
    const schemaKnowsCapabilities = requiredCapabilityKeys.every((key) => schemaText.includes(`"${key}"`));
    if (missingCapabilities.length > 0 || !schemaKnowsCapabilities) {
      addFinding({
        id: check.id,
        title: check.title,
        severity: check.severity,
        summary: 'The multi-fork catalog still relies on free-text purpose and partial remote metadata; explicit push/mount eligibility is not yet part of the contract.',
        standards: check.standards,
        evidence: [
          {
            path: relativeFrom(repoRoot, instancePaths[0]),
            line: lineOf(instanceTexts[0], 'forks:'),
            detail: `Owned fork entries do not declare ${requiredCapabilityKeys.join(' and ')}.`
          },
          {
            path: 'docs/schemas/fork-lane-instance-v1.schema.json',
            line: lineOf(instanceSchemaText, '"forks"'),
            detail: 'The instance schema does not currently require explicit fork capability attributes.'
          }
        ],
        actionItem: buildActionItem(check, check.id, 'Add explicit operational capability fields for each owned fork so selection is governed by contract attributes rather than purpose text.')
      });
    } else {
      addPass({
        id: check.id,
        title: check.title,
        severity: 'info',
        summary: 'Each owned fork declares explicit operational capability attributes.',
        standards: check.standards,
        evidence: [
          { path: relativeFrom(repoRoot, instancePaths[0]), detail: 'Owned fork entries carry explicit capability attributes.' }
        ]
      });
    }
  }

  {
    const check = checks.get('lifecycle-closure-contract');
    const hasConditionalLifecycleRules = Boolean(instanceSchema.allOf) && JSON.stringify(instanceSchema).includes('closed_at') && JSON.stringify(instanceSchema).includes('superseded_by_issue');
    if (!hasConditionalLifecycleRules) {
      addFinding({
        id: check.id,
        title: check.title,
        severity: check.severity,
        summary: 'Lifecycle state is recorded, but closure and supersession evidence are not yet conditionally enforced by the instance contract.',
        standards: check.standards,
        evidence: [
          {
            path: 'docs/schemas/fork-lane-instance-v1.schema.json',
            line: lineOf(instanceSchemaText, '"lifecycle"'),
            detail: 'The schema defines closure fields but does not conditionally require them when status changes.'
          }
        ],
        actionItem: buildActionItem(check, check.id, 'Add conditional lifecycle rules so closed and superseded states carry mandatory closure evidence.')
      });
    } else {
      addPass({
        id: check.id,
        title: check.title,
        severity: 'info',
        summary: 'Lifecycle closure and supersession conditions are enforced by contract.',
        standards: check.standards,
        evidence: [
          { path: 'docs/schemas/fork-lane-instance-v1.schema.json', detail: 'Conditional lifecycle rules are present.' }
        ]
      });
    }
  }

  const blockingCount = findings.filter((finding) => finding.status === 'finding' && finding.severity === 'high').length;
  const actionableCount = findings.filter((finding) => finding.status === 'finding').length;
  const overallStatus = blockingCount > 0 ? 'fail' : (actionableCount > 0 ? 'pass-with-actions' : 'pass');

  const report = {
    schema: 'comparevi/fork-lane-design-audit-report@v1',
    generatedAtUtc: new Date().toISOString(),
    subject: {
      activeIssue: index.active_issue,
      indexPath: relativeFrom(repoRoot, resolved.indexPath),
      templatePath: relativeFrom(repoRoot, resolved.templatePath),
      instancePaths: instancePaths.map((filePath) => relativeFrom(repoRoot, filePath)),
      policyPath: relativeFrom(repoRoot, resolved.policyPath)
    },
    overall: {
      status: overallStatus,
      findingCount: actionableCount,
      actionItemCount: actionItems.length,
      blockingCount
    },
    findings,
    actionItems
  };

  const summaryLines = [
    '# Fork Lane Design Audit',
    '',
    `- Status: \`${report.overall.status}\``,
    `- Findings: \`${report.overall.findingCount}\``,
    `- Action items: \`${report.overall.actionItemCount}\``,
    `- Blocking findings: \`${report.overall.blockingCount}\``,
    ''
  ];

  if (report.findings.length > 0) {
    summaryLines.push('## Findings', '');
    for (const finding of report.findings) {
      summaryLines.push(`- [${finding.status === 'finding' ? 'open' : 'pass'}] \`${finding.id}\` (${finding.severity})`);
      summaryLines.push(`  ${finding.summary}`);
      summaryLines.push(`  Standards: ${finding.standards.join(', ')}`);
      for (const evidence of finding.evidence) {
        summaryLines.push(`  Evidence: \`${evidence.path}${evidence.line ? `:${evidence.line}` : ''}\` - ${evidence.detail}`);
      }
    }
    summaryLines.push('');
  }

  if (report.actionItems.length > 0) {
    summaryLines.push('## Action Items', '');
    for (const item of report.actionItems) {
      summaryLines.push(`- \`${item.id}\` (${item.priority}) ${item.title}`);
      summaryLines.push(`  ${item.description}`);
      summaryLines.push(`  Standards: ${item.standards.join(', ')}`);
      for (const criterion of item.acceptance) {
        summaryLines.push(`  Acceptance: ${criterion}`);
      }
    }
  }

  await fs.mkdir(path.dirname(resolved.outputPath), { recursive: true });
  await fs.writeFile(resolved.outputPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  await fs.writeFile(resolved.summaryPath, `${summaryLines.join('\n')}\n`, 'utf8');

  return { report, summary: summaryLines.join('\n') };
}

async function main() {
  const options = parseArgs();
  if (options.help) {
    printHelp();
    return;
  }
  const { report } = await runForkLaneDesignAudit(options);
  console.log(`status=${report.overall.status}`);
  console.log(`findings=${report.overall.findingCount}`);
  console.log(`action_items=${report.overall.actionItemCount}`);
  if (report.overall.blockingCount > 0) {
    process.exitCode = 1;
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.stack || error.message : String(error));
    process.exitCode = 1;
  });
}
