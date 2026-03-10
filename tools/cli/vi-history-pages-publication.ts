import '../shims/punycode-userland.js';
import { createHash } from 'node:crypto';
import {
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { dirname, join, posix, relative, resolve } from 'node:path';
import { ArgumentParser } from 'argparse';
import { z } from 'zod';

interface Args {
  suite: string;
  output_dir: string;
  source_repository: string;
  source_workflow: string;
  source_run_id: number;
  source_run_attempt?: number;
  pages_base_url?: string;
  publication_root?: string;
  scenario_label?: string;
  slice_digest?: string;
  step_summary?: string;
}

type DigestSource = 'explicit' | 'suite' | 'derived';
type FileKind = 'history-report' | 'preview-image' | 'suite-manifest' | 'suite-asset' | 'landing-page';

interface FileRecord {
  relativePath: string;
  kind: FileKind;
  sha256: string;
  byteLength: number;
}

interface PreviewRecord {
  relativePath: string;
  alt: string | null;
  sha256: string;
  byteLength: number;
  indexPath: string;
  imageOrdinal: number;
}

const countMapSchema = z.record(z.string(), z.number().int().nonnegative());

const modeStatsSchema = z.object({
  processed: z.number().int().nonnegative(),
  diffs: z.number().int().nonnegative(),
  signalDiffs: z.number().int().nonnegative(),
  noiseCollapsed: z.number().int().nonnegative(),
  errors: z.number().int().nonnegative(),
  missing: z.number().int().nonnegative(),
  categoryCounts: countMapSchema.optional().default({}),
  bucketCounts: countMapSchema.optional().default({}),
}).passthrough();

const suiteModeSchema = z.object({
  name: z.string().min(1),
  slug: z.string().min(1),
  flags: z.array(z.string()).default([]),
  manifestPath: z.string().optional(),
  resultsDir: z.string().optional(),
  stats: modeStatsSchema,
  status: z.string().min(1),
}).passthrough();

const suiteManifestSchema = z.object({
  schema: z.literal('vi-compare/history-suite@v1'),
  generatedAt: z.string().min(1),
  targetPath: z.string().min(1),
  requestedStartRef: z.string().min(1),
  startRef: z.string().min(1),
  endRef: z.string().nullable().optional(),
  reportFormat: z.string().min(1),
  resultsDir: z.string().min(1),
  requestedModes: z.array(z.string().min(1)),
  executedModes: z.array(z.string().min(1)),
  modes: z.array(suiteModeSchema),
  stats: modeStatsSchema.extend({
    modes: z.number().int().nonnegative().optional(),
  }).passthrough(),
  status: z.string().min(1),
  sliceDigest: z.string().min(1).optional(),
}).passthrough();

const imageIndexSchema = z.object({
  schema: z.literal('pr-vi-history-image-index@v1'),
  reportPath: z.string().optional(),
  outputDir: z.string().optional(),
  sourceImageCount: z.number().int().nonnegative().optional(),
  exportedImageCount: z.number().int().nonnegative().optional(),
  images: z.array(z.object({
    index: z.number().int().nonnegative().optional(),
    fileName: z.string().optional(),
    savedPath: z.string().optional(),
    alt: z.string().nullable().optional(),
    status: z.string().optional(),
  }).passthrough()).default([]),
}).passthrough();

type SuiteManifest = z.infer<typeof suiteManifestSchema>;
type ImageIndex = z.infer<typeof imageIndexSchema>;

function readJson<T>(path: string): T {
  try {
    return JSON.parse(readFileSync(path, 'utf8')) as T;
  } catch (error) {
    throw new Error(`Failed to parse JSON from ${path}: ${(error as Error).message}`);
  }
}

function ensureDirectory(path: string): string {
  mkdirSync(path, { recursive: true });
  return path;
}

function toPosixPath(pathValue: string): string {
  return pathValue.replace(/\\/g, '/');
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function stableStringify(value: unknown): string {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value);
  }

  if (Array.isArray(value)) {
    return `[${value.map((entry) => stableStringify(entry)).join(',')}]`;
  }

  const objectValue = value as Record<string, unknown>;
  const keys = Object.keys(objectValue).sort((a, b) => a.localeCompare(b));
  const body = keys.map((key) => `${JSON.stringify(key)}:${stableStringify(objectValue[key])}`).join(',');
  return `{${body}}`;
}

function sha256Text(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}

function sha256File(path: string): string {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

function parseRepositorySegments(repository: string): string[] {
  const trimmed = repository.trim().replace(/^https:\/\/github\.com\//i, '').replace(/\.git$/i, '');
  const segments = trimmed.split('/').map((segment) => segment.trim()).filter((segment) => segment.length > 0);
  if (segments.length < 2) {
    throw new Error(`source-repository must look like owner/repo. Received '${repository}'.`);
  }
  return segments.slice(0, 2);
}

function resolvePathWithin(root: string, pathValue: string): string {
  return resolve(root, pathValue);
}

function walkFiles(root: string): string[] {
  const files: string[] = [];
  const pending = [root];
  while (pending.length > 0) {
    const current = pending.pop();
    if (!current) {
      continue;
    }

    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const fullPath = join(current, entry.name);
      if (entry.isDirectory()) {
        pending.push(fullPath);
      } else if (entry.isFile()) {
        files.push(fullPath);
      }
    }
  }

  return files.sort((left, right) => left.localeCompare(right));
}

function resolveSuiteRoot(suiteManifestPath: string, suite: SuiteManifest): string {
  const manifestDirectory = dirname(suiteManifestPath);
  const candidate = resolvePathWithin(manifestDirectory, suite.resultsDir);
  if (existsSync(candidate) && statSync(candidate).isDirectory()) {
    return candidate;
  }
  return manifestDirectory;
}

function findImageIndexPaths(root: string): string[] {
  return walkFiles(root).filter((filePath) => filePath.endsWith('vi-history-image-index.json'));
}

function resolvePreviewRecord(
  suiteRoot: string,
  indexPath: string,
  indexPayload: ImageIndex,
): PreviewRecord[] {
  const indexDirectory = dirname(indexPath);
  const previews: PreviewRecord[] = [];

  for (const [ordinal, image] of (indexPayload.images ?? []).entries()) {
    if (image.status && image.status !== 'saved') {
      continue;
    }

    const candidatePaths = [
      image.savedPath,
      image.fileName ? join(indexDirectory, image.fileName) : undefined,
      image.fileName && indexPayload.outputDir ? join(resolve(indexDirectory, indexPayload.outputDir), image.fileName) : undefined,
    ].filter((value): value is string => typeof value === 'string' && value.trim().length > 0);

    const resolvedCandidate = candidatePaths
      .map((candidate) => resolve(candidate))
      .find((candidate) => existsSync(candidate) && statSync(candidate).isFile());

    if (!resolvedCandidate) {
      continue;
    }

    const relativePath = toPosixPath(relative(suiteRoot, resolvedCandidate));
    if (relativePath.startsWith('..')) {
      continue;
    }

    previews.push({
      relativePath,
      alt: image.alt ?? null,
      sha256: sha256File(resolvedCandidate),
      byteLength: statSync(resolvedCandidate).size,
      indexPath: toPosixPath(relative(suiteRoot, indexPath)),
      imageOrdinal: image.index ?? ordinal,
    });
  }

  return previews;
}

function findFirstRelativePath(root: string, fileName: string): string | null {
  const needle = `/${fileName}`.toLowerCase();
  const match = walkFiles(root).find((candidate) => toPosixPath(candidate).toLowerCase().endsWith(needle));
  if (!match) {
    return null;
  }
  return toPosixPath(relative(root, match));
}

function normalizeCountMap(map: Record<string, number> | undefined): Record<string, number> {
  const entries = Object.entries(map ?? {}).sort((left, right) => left[0].localeCompare(right[0]));
  return Object.fromEntries(entries);
}

function computePublicationKey(
  suite: SuiteManifest,
  previews: PreviewRecord[],
  explicitDigest?: string,
): { publicationKey: string; digestSource: DigestSource } {
  if (explicitDigest && explicitDigest.trim().length > 0) {
    return { publicationKey: explicitDigest.trim(), digestSource: 'explicit' };
  }

  if (suite.sliceDigest && suite.sliceDigest.trim().length > 0) {
    return { publicationKey: suite.sliceDigest.trim(), digestSource: 'suite' };
  }

  const canonicalPayload = {
    schema: suite.schema,
    targetPath: suite.targetPath,
    requestedStartRef: suite.requestedStartRef,
    startRef: suite.startRef,
    endRef: suite.endRef ?? null,
    reportFormat: suite.reportFormat,
    requestedModes: [...suite.requestedModes],
    executedModes: [...suite.executedModes],
    status: suite.status,
    aggregateStats: {
      processed: suite.stats.processed,
      diffs: suite.stats.diffs,
      signalDiffs: suite.stats.signalDiffs,
      noiseCollapsed: suite.stats.noiseCollapsed,
      errors: suite.stats.errors,
      missing: suite.stats.missing,
      categoryCounts: normalizeCountMap(suite.stats.categoryCounts),
      bucketCounts: normalizeCountMap(suite.stats.bucketCounts),
    },
    modes: suite.modes.map((mode) => ({
      slug: mode.slug,
      flags: [...mode.flags],
      status: mode.status,
      stats: {
        processed: mode.stats.processed,
        diffs: mode.stats.diffs,
        signalDiffs: mode.stats.signalDiffs,
        noiseCollapsed: mode.stats.noiseCollapsed,
        errors: mode.stats.errors,
        missing: mode.stats.missing,
        categoryCounts: normalizeCountMap(mode.stats.categoryCounts),
        bucketCounts: normalizeCountMap(mode.stats.bucketCounts),
      },
    })),
    previews: previews.map((preview) => ({
      relativePath: preview.relativePath,
      sha256: preview.sha256,
    })),
  };

  return {
    publicationKey: sha256Text(stableStringify(canonicalPayload)),
    digestSource: 'derived',
  };
}

function createFileInventory(root: string, historyReportPath: string | null): FileRecord[] {
  return walkFiles(root)
    .filter((filePath) => toPosixPath(relative(root, filePath)) !== 'publication.json')
    .map((filePath) => {
    const relativePath = toPosixPath(relative(root, filePath));
    let kind: FileKind = 'suite-asset';
    if (relativePath === 'index.html') {
      kind = 'landing-page';
    } else if (relativePath === 'suite/manifest.json') {
      kind = 'suite-manifest';
    } else if (historyReportPath && relativePath === historyReportPath) {
      kind = 'history-report';
    } else if (relativePath.includes('/previews/') || relativePath.includes('/preview/')) {
      kind = 'preview-image';
    }

    return {
      relativePath,
      kind,
      sha256: sha256File(filePath),
      byteLength: statSync(filePath).size,
    };
  });
}

function buildLandingPage(params: {
  sourceRepository: string;
  sourceWorkflow: string;
  sourceRunId: number;
  sourceRunAttempt: number;
  scenarioLabel: string | null;
  publicationKey: string;
  digestSource: DigestSource;
  suite: SuiteManifest;
  historyReportRelativePath: string | null;
  siteUrl: string | null;
  previews: PreviewRecord[];
  publicationPath: string;
}): string {
  const previewCards = params.previews.length > 0
    ? params.previews.map((preview) => {
      const altText = preview.alt ?? `${params.suite.targetPath} preview ${preview.imageOrdinal}`;
      return [
        '<article class="preview-card">',
        `  <img src="./suite/${escapeHtml(preview.relativePath)}" alt="${escapeHtml(altText)}">`,
        '  <div class="preview-meta">',
        `    <strong>${escapeHtml(altText)}</strong>`,
        `    <div><code>${escapeHtml(preview.relativePath)}</code></div>`,
        `    <div>sha256: <code>${escapeHtml(preview.sha256.slice(0, 16))}</code></div>`,
        '  </div>',
        '</article>',
      ].join('\n');
    }).join('\n')
    : '<p class="empty">No preview images were discovered in the suite bundle.</p>';

  const historyLink = params.historyReportRelativePath
    ? `<a href="./suite/${escapeHtml(params.historyReportRelativePath)}">Open consolidated VI History report</a>`
    : 'No consolidated history-report.html was discovered in the suite root.';

  const siteUrlLine = params.siteUrl
    ? `<div>Published URL: <code>${escapeHtml(params.siteUrl)}</code></div>`
    : '<div>Published URL: resolved at deploy time</div>';

  const scenarioLine = params.scenarioLabel
    ? `<div>Scenario: <strong>${escapeHtml(params.scenarioLabel)}</strong></div>`
    : '';

  return [
    '<!doctype html>',
    '<html lang="en">',
    '<head>',
    '  <meta charset="utf-8">',
    '  <meta name="viewport" content="width=device-width, initial-scale=1">',
    `  <title>${escapeHtml(params.suite.targetPath)} VI History review site</title>`,
    '  <style>',
    '    :root { color-scheme: light; --bg: #f5f1e8; --ink: #1f2933; --card: #fffdfa; --accent: #0b7285; --muted: #6b7280; --line: #d9cfbf; }',
    '    body { margin: 0; font-family: Georgia, "Times New Roman", serif; background: radial-gradient(circle at top, #fff8e8, var(--bg)); color: var(--ink); }',
    '    main { max-width: 1100px; margin: 0 auto; padding: 40px 24px 64px; }',
    '    .hero { background: rgba(255,255,255,0.88); border: 1px solid var(--line); border-radius: 24px; padding: 28px; box-shadow: 0 18px 48px rgba(31,41,51,0.08); }',
    '    h1, h2 { margin: 0 0 12px; }',
    '    p { line-height: 1.5; }',
    '    .meta { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; margin-top: 18px; }',
    '    .meta div { background: var(--card); border: 1px solid var(--line); border-radius: 16px; padding: 12px 14px; }',
    '    .actions { display: flex; gap: 14px; flex-wrap: wrap; margin-top: 18px; }',
    '    .actions a { color: white; background: var(--accent); text-decoration: none; padding: 10px 14px; border-radius: 999px; }',
    '    .actions a.secondary { background: transparent; color: var(--accent); border: 1px solid var(--accent); }',
    '    .stats { margin-top: 26px; display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 10px; }',
    '    .stats div { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 12px; }',
    '    .previews { margin-top: 28px; display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 18px; }',
    '    .preview-card { background: var(--card); border: 1px solid var(--line); border-radius: 18px; overflow: hidden; box-shadow: 0 10px 24px rgba(31,41,51,0.06); }',
    '    .preview-card img { display: block; width: 100%; height: 220px; object-fit: contain; background: #fbf6ec; }',
    '    .preview-meta { padding: 12px 14px 16px; font-size: 0.94rem; }',
    '    .empty { color: var(--muted); font-style: italic; }',
    '    code { font-family: "Cascadia Code", "SFMono-Regular", Consolas, monospace; font-size: 0.92em; }',
    '  </style>',
    '</head>',
    '<body>',
    '  <main>',
    '    <section class="hero">',
    `      <h1>${escapeHtml(params.suite.targetPath)}</h1>`,
    '      <p>Static review surface for a VI History suite. The site is keyed by a content-addressed publication identity so humans can inspect preview images and request follow-on epics against a stable artifact.</p>',
    `      <div><strong>Publication key:</strong> <code>${escapeHtml(params.publicationKey)}</code> <span>(${escapeHtml(params.digestSource)})</span></div>`,
    `      <div><strong>Publication path:</strong> <code>${escapeHtml(params.publicationPath)}</code></div>`,
    `      ${siteUrlLine}`,
    `      ${scenarioLine}`,
    '      <div class="meta">',
    `        <div><strong>Repository</strong><br>${escapeHtml(params.sourceRepository)}</div>`,
    `        <div><strong>Workflow</strong><br>${escapeHtml(params.sourceWorkflow)}</div>`,
    `        <div><strong>Run</strong><br>${params.sourceRunId} / attempt ${params.sourceRunAttempt}</div>`,
    `        <div><strong>Modes</strong><br>${escapeHtml(params.suite.executedModes.join(', ') || 'none')}</div>`,
    '      </div>',
    '      <div class="actions">',
    '        <a href="./suite/manifest.json">Open suite manifest</a>',
    '        <a class="secondary" href="./publication.json">Open publication manifest</a>',
    '        <a class="secondary" href="./suite/">Browse copied suite root</a>',
    '      </div>',
    `      <div class="actions"><span>${historyLink}</span></div>`,
    '      <div class="stats">',
    `        <div><strong>Processed</strong><br>${params.suite.stats.processed}</div>`,
    `        <div><strong>Diffs</strong><br>${params.suite.stats.diffs}</div>`,
    `        <div><strong>Signal</strong><br>${params.suite.stats.signalDiffs}</div>`,
    `        <div><strong>Missing</strong><br>${params.suite.stats.missing}</div>`,
    `        <div><strong>Previews</strong><br>${params.previews.length}</div>`,
    '      </div>',
    '    </section>',
    '    <section>',
    '      <h2>Preview Gallery</h2>',
    `      <div class="previews">${previewCards}</div>`,
    '    </section>',
    '  </main>',
    '</body>',
    '</html>',
  ].join('\n');
}

function appendStepSummary(stepSummaryPath: string, lines: string[]): void {
  writeFileSync(stepSummaryPath, `\n${lines.join('\n')}\n`, { encoding: 'utf8', flag: 'a' });
}

function main(): void {
  const parser = new ArgumentParser({
    description: 'Prepare a static VI History review site package suitable for GitHub Pages publication.',
  });

  parser.add_argument('--suite', { required: true, help: 'Path to the vi-compare/history-suite@v1 manifest.' });
  parser.add_argument('--output-dir', { required: true, help: 'Directory where the static review site package should be written.' });
  parser.add_argument('--source-repository', { required: true, help: 'GitHub repository slug (owner/repo).' });
  parser.add_argument('--source-workflow', { required: true, help: 'Workflow name that produced the suite artifact.' });
  parser.add_argument('--source-run-id', { required: true, type: 'int', help: 'Workflow run id that produced the suite artifact.' });
  parser.add_argument('--source-run-attempt', { required: false, type: 'int', default: 1, help: 'Workflow run attempt number.' });
  parser.add_argument('--pages-base-url', { required: false, help: 'Optional base URL for the GitHub Pages site.' });
  parser.add_argument('--publication-root', { required: false, default: 'vi-history-smoke', help: 'Relative root path to use inside the Pages site.' });
  parser.add_argument('--scenario-label', { required: false, help: 'Optional human-facing scenario label.' });
  parser.add_argument('--slice-digest', { required: false, help: 'Optional explicit immutable slice digest.' });
  parser.add_argument('--step-summary', { required: false, help: 'Optional GitHub Step Summary path to append publication details to.' });

  const args = parser.parse_args() as Args;
  const suiteManifestPath = resolve(process.cwd(), args.suite);
  if (!existsSync(suiteManifestPath)) {
    throw new Error(`Suite manifest not found: ${suiteManifestPath}`);
  }

  const suite = suiteManifestSchema.parse(readJson<unknown>(suiteManifestPath));
  const suiteRoot = resolveSuiteRoot(suiteManifestPath, suite);
  const historyReportRelativePath = findFirstRelativePath(suiteRoot, 'history-report.html');
  const previewIndexes = findImageIndexPaths(suiteRoot);
  const previews = previewIndexes.flatMap((indexPath) => {
    const payload = imageIndexSchema.parse(readJson<unknown>(indexPath));
    return resolvePreviewRecord(suiteRoot, indexPath, payload);
  });

  const { publicationKey, digestSource } = computePublicationKey(suite, previews, args.slice_digest);
  const repositorySegments = parseRepositorySegments(args.source_repository);
  const publicationPath = posix.join(
    args.publication_root ?? 'vi-history-smoke',
    ...repositorySegments,
    publicationKey,
    `run-${args.source_run_id}-attempt-${args.source_run_attempt ?? 1}`,
  );
  const baseUrl = args.pages_base_url ? args.pages_base_url.replace(/\/+$/u, '') : null;
  const siteUrl = baseUrl ? `${baseUrl}/${publicationPath}/index.html` : null;

  const outputRoot = ensureDirectory(resolve(process.cwd(), args.output_dir));
  const suiteOutputRoot = ensureDirectory(join(outputRoot, 'suite'));
  cpSync(suiteRoot, suiteOutputRoot, { recursive: true, force: true });

  const landingPage = buildLandingPage({
    sourceRepository: args.source_repository,
    sourceWorkflow: args.source_workflow,
    sourceRunId: args.source_run_id,
    sourceRunAttempt: args.source_run_attempt ?? 1,
    scenarioLabel: args.scenario_label ?? null,
    publicationKey,
    digestSource,
    suite,
    historyReportRelativePath,
    siteUrl,
    previews,
    publicationPath,
  });
  writeFileSync(join(outputRoot, 'index.html'), `${landingPage}\n`, 'utf8');

  const preliminaryInventory = createFileInventory(
    outputRoot,
    historyReportRelativePath ? `suite/${historyReportRelativePath}` : null,
  );
  const publicationSummary = {
    schema: 'vi-history-pages-publication@v1',
    generatedAt: new Date().toISOString(),
    publicationKey,
    digestSource,
    publicationPath,
    siteUrl,
    pagesBaseUrl: baseUrl,
    scenarioLabel: args.scenario_label ?? null,
    source: {
      repository: args.source_repository,
      workflow: args.source_workflow,
      runId: args.source_run_id,
      runAttempt: args.source_run_attempt ?? 1,
    },
    suite: {
      schema: suite.schema,
      targetPath: suite.targetPath,
      requestedStartRef: suite.requestedStartRef,
      startRef: suite.startRef,
      endRef: suite.endRef ?? null,
      requestedModes: [...suite.requestedModes],
      executedModes: [...suite.executedModes],
      reportFormat: suite.reportFormat,
      status: suite.status,
      stats: {
        processed: suite.stats.processed,
        diffs: suite.stats.diffs,
        signalDiffs: suite.stats.signalDiffs,
        noiseCollapsed: suite.stats.noiseCollapsed,
        errors: suite.stats.errors,
        missing: suite.stats.missing,
        categoryCounts: normalizeCountMap(suite.stats.categoryCounts),
        bucketCounts: normalizeCountMap(suite.stats.bucketCounts),
      },
      historyReportPath: historyReportRelativePath ? `suite/${historyReportRelativePath}` : null,
    },
    previews: {
      imageIndexCount: previewIndexes.length,
      publishedImageCount: previews.length,
      missingImageCount: 0,
      items: previews.map((preview) => ({
        relativePath: `suite/${preview.relativePath}`,
        alt: preview.alt,
        sha256: preview.sha256,
        byteLength: preview.byteLength,
        sourceIndexPath: `suite/${preview.indexPath}`,
        imageOrdinal: preview.imageOrdinal,
      })),
    },
    files: preliminaryInventory,
    status: 'prepared',
  };

  writeFileSync(join(outputRoot, 'publication.json'), `${JSON.stringify(publicationSummary, null, 2)}\n`, 'utf8');

  const finalInventory = createFileInventory(
    outputRoot,
    historyReportRelativePath ? `suite/${historyReportRelativePath}` : null,
  );
  publicationSummary.files = finalInventory;
  writeFileSync(join(outputRoot, 'publication.json'), `${JSON.stringify(publicationSummary, null, 2)}\n`, 'utf8');

  if (args.step_summary) {
    appendStepSummary(resolve(process.cwd(), args.step_summary), [
      '### VI History Pages Publication Plan',
      '',
      `- publication_key: \`${publicationKey}\` (${digestSource})`,
      `- publication_path: \`${publicationPath}\``,
      `- preview_images: \`${previews.length}\``,
      `- copied_suite_root: \`${suiteRoot}\``,
      `- output_dir: \`${outputRoot}\``,
      ...(siteUrl ? [`- site_url: \`${siteUrl}\``] : []),
    ]);
  }

  // eslint-disable-next-line no-console
  console.log(JSON.stringify({
    schema: 'vi-history-pages-publication-result@v1',
    publicationKey,
    publicationPath,
    siteUrl,
    outputDir: outputRoot,
    previewImageCount: previews.length,
  }, null, 2));
}

main();
