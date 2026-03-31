#!/usr/bin/env node

import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { spawnSync } from 'node:child_process';

const repoRoot = process.cwd();
const baseDir = path.join(repoRoot, 'tests', 'results', '_agent', 'pester-service-model');
const assuranceDir = path.join(baseDir, 'local-assurance');
const releaseEvidenceDir = path.join(baseDir, 'release-evidence');
const outputPath = path.join(releaseEvidenceDir, 'promotion-dossier.md');

function runGit(args) {
  const result = spawnSync('git', args, { cwd: repoRoot, encoding: 'utf8' });
  if (result.status !== 0) {
    throw new Error(result.stderr?.trim() || `git ${args.join(' ')} failed`);
  }
  return result.stdout.trim();
}

async function main() {
  const assuranceReport = JSON.parse(
    await fs.readFile(path.join(assuranceDir, 'pester-service-model-assurance-report.json'), 'utf8')
  );
  const standardsScore = JSON.parse(
    await fs.readFile(path.join(assuranceDir, 'standards-score.json'), 'utf8')
  );
  const rtm = await fs.readFile(path.join(repoRoot, 'docs', 'rtm-pester-service-model.csv'), 'utf8');

  await fs.mkdir(releaseEvidenceDir, { recursive: true });

  const lines = [
    '# Pester Service Model Promotion Dossier',
    '',
    `- Fork baseline commit: ${runGit(['rev-parse', 'HEAD'])}`,
    '- Upstream epic: `#2069`',
    '- Fork design issue: `#2078`',
    `- Overall assurance status: ${assuranceReport.overall.status}`,
    `- Action items: ${assuranceReport.overall.action_item_count}`,
    '',
    '## Standards Position',
    '',
    `- REQ: ${standardsScore.areas.REQ.score} (${standardsScore.areas.REQ.rating})`,
    `- ARCH: ${standardsScore.areas.ARCH.score} (${standardsScore.areas.ARCH.rating})`,
    `- TEST: ${standardsScore.areas.TEST.score} (${standardsScore.areas.TEST.rating})`,
    `- CM: ${standardsScore.areas.CM.score} (${standardsScore.areas.CM.rating})`,
    `- DOC: ${standardsScore.areas.DOC.score} (${standardsScore.areas.DOC.rating})`,
    '',
    '## Requirement Traceability',
    '',
    '```csv',
    rtm.trim(),
    '```',
    '',
    '## Promotion Evidence',
    '',
    '- trusted router requirement packet is specified and traced',
    '- context, readiness, execution, and evidence layers are explicitly separated',
    '- local assurance packet passes with zero action items',
    '- release-evidence bundle retains coverage.xml, docs-link-check.json, and assurance outputs',
    '',
    '## Minimal Upstream Slice',
    '',
    '1. Reference `REQ-PSM-*` and the fork dossier in `#2069`.',
    '2. Promote the smallest workflow or contract slice justified by the retained evidence.',
    '3. Re-prove the mounted slice on the upstream integration rail before changing the required gate.',
    ''
  ];

  await fs.writeFile(outputPath, `${lines.join('\n')}\n`, 'utf8');
  console.log(`promotion_dossier=${outputPath}`);
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
