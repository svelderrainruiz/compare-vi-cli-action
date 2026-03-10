import '../shims/punycode-userland.js';
import { createHash } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, posix, relative, resolve } from 'node:path';
import { ArgumentParser } from 'argparse';
import { z } from 'zod';

interface Args {
  output_dir: string;
  publication_dir?: string[];
  scan_root?: string;
  pages_base_url?: string;
  catalog_path_root?: string;
  epic_repository?: string;
  epic_template?: string;
  epic_label?: string[];
  step_summary?: string;
}

const publicationSchema = z.object({
  schema: z.literal('vi-history-pages-publication@v1'),
  generatedAt: z.string().min(1),
  publicationKey: z.string().min(1),
  publicationPath: z.string().min(1),
  siteUrl: z.string().nullable().optional(),
  source: z.object({
    repository: z.string().min(1),
    workflow: z.string().min(1),
    runId: z.number().int().positive(),
    runAttempt: z.number().int().positive(),
  }),
  suite: z.object({
    targetPath: z.string().min(1),
    startRef: z.string().min(1),
    status: z.string().min(1),
    executedModes: z.array(z.string().min(1)),
    historyReportPath: z.string().nullable().optional(),
  }).passthrough(),
  previews: z.object({
    publishedImageCount: z.number().int().nonnegative(),
    items: z.array(z.object({
      relativePath: z.string().min(1),
    }).passthrough()).default([]),
  }).passthrough(),
}).passthrough();

type PublicationManifest = z.infer<typeof publicationSchema>;

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

function toPosixPath(value: string): string {
  return value.replace(/\\/g, '/');
}

function escapeHtml(value: string): string {
  return value
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
  return `{${keys.map((key) => `${JSON.stringify(key)}:${stableStringify(objectValue[key])}`).join(',')}}`;
}

function sha256Text(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}

function normalizeLabels(values: string[] | undefined): string[] {
  const labels = (values ?? [])
    .flatMap((entry) => entry.split(','))
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);

  return [...new Set(labels)].sort((left, right) => left.localeCompare(right));
}

function walkDirectories(root: string): string[] {
  const pending = [root];
  const directories: string[] = [];
  while (pending.length > 0) {
    const current = pending.pop();
    if (!current) {
      continue;
    }

    directories.push(current);
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      if (!entry.isDirectory()) {
        continue;
      }
      pending.push(join(current, entry.name));
    }
  }

  return directories.sort((left, right) => left.localeCompare(right));
}

function findPublicationDirs(scanRoot: string): string[] {
  return walkDirectories(scanRoot)
    .filter((directoryPath) => existsSync(join(directoryPath, 'publication.json')));
}

function buildIssueUrl(repository: string, template: string, title: string, labels: string[]): string {
  const query = new URLSearchParams({
    template,
    title,
  });

  if (labels.length > 0) {
    query.set('labels', labels.join(','));
  }

  return `https://github.com/${repository}/issues/new?${query.toString()}`;
}

function buildEpicRequest(
  publication: PublicationManifest,
  epicRepository: string,
  epicTemplate: string,
  epicLabels: string[],
): {
  repository: string;
  template: string;
  labels: string[];
  title: string;
  issueUrl: string;
  bodyLines: string[];
} {
  const title = `VI History review follow-up: ${publication.suite.targetPath} [${publication.publicationKey.slice(0, 12)}]`;
  const bodyLines = [
    `Publication key: ${publication.publicationKey}`,
    `Publication path: ${publication.publicationPath}`,
    `Source workflow: ${publication.source.workflow}`,
    `Source run: ${publication.source.runId} / attempt ${publication.source.runAttempt}`,
    `Target VI: ${publication.suite.targetPath}`,
    `Review URL: ${publication.siteUrl ?? publication.publicationPath}`,
  ];

  return {
    repository: epicRepository,
    template: epicTemplate,
    labels: epicLabels,
    title,
    issueUrl: buildIssueUrl(epicRepository, epicTemplate, title, epicLabels),
    bodyLines,
  };
}

function buildCatalogIndex(entries: Array<{
  publicationKey: string;
  publicationPath: string;
  siteUrl: string | null;
  source: PublicationManifest['source'];
  suite: PublicationManifest['suite'];
  previews: { publishedImageCount: number; heroImagePath: string | null };
  epicRequest: ReturnType<typeof buildEpicRequest>;
}>): string {
  const cards = entries.map((entry) => {
    const hero = entry.previews.heroImagePath
      ? `<img src="./${escapeHtml(entry.publicationPath)}/${escapeHtml(entry.previews.heroImagePath)}" alt="${escapeHtml(entry.suite.targetPath)} preview">`
      : '<div class="placeholder">No preview image</div>';
    return [
      '<article class="card">',
      `  ${hero}`,
      '  <div class="content">',
      `    <h2><a href="./${escapeHtml(entry.publicationPath)}/index.html">${escapeHtml(entry.suite.targetPath)}</a></h2>`,
      `    <div class="meta">Publication <code>${escapeHtml(entry.publicationKey)}</code></div>`,
      `    <div class="meta">Run ${entry.source.runId} / attempt ${entry.source.runAttempt} · ${escapeHtml(entry.source.repository)}</div>`,
      `    <div class="meta">Modes: ${escapeHtml(entry.suite.executedModes.join(', '))}</div>`,
      `    <div class="meta">Previews: ${entry.previews.publishedImageCount}</div>`,
      '    <div class="actions">',
      `      <a href="./${escapeHtml(entry.publicationPath)}/index.html">Open review site</a>`,
      `      <a class="secondary" href="${escapeHtml(entry.epicRequest.issueUrl)}">Request new epic</a>`,
      '    </div>',
      `    <details><summary>Epic request stub</summary><pre>${escapeHtml(entry.epicRequest.bodyLines.join('\n'))}</pre></details>`,
      '  </div>',
      '</article>',
    ].join('\n');
  }).join('\n');

  return [
    '<!doctype html>',
    '<html lang="en">',
    '<head>',
    '  <meta charset="utf-8">',
    '  <meta name="viewport" content="width=device-width, initial-scale=1">',
    '  <title>VI History review catalog</title>',
    '  <style>',
    '    :root { --bg: #eef4f1; --ink: #1f2933; --card: #ffffff; --line: #d0ddd7; --accent: #0f766e; --muted: #5b6770; }',
    '    body { margin: 0; font-family: Georgia, "Times New Roman", serif; color: var(--ink); background: linear-gradient(180deg, #f6faf8, var(--bg)); }',
    '    main { max-width: 1200px; margin: 0 auto; padding: 40px 24px 64px; }',
    '    h1 { margin: 0 0 10px; }',
    '    .lead { max-width: 760px; line-height: 1.5; color: var(--muted); }',
    '    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 20px; margin-top: 28px; }',
    '    .card { background: var(--card); border: 1px solid var(--line); border-radius: 22px; overflow: hidden; box-shadow: 0 14px 36px rgba(31,41,51,0.08); }',
    '    .card img, .placeholder { width: 100%; height: 220px; object-fit: contain; display: block; background: #f4f7f5; }',
    '    .placeholder { display: flex; align-items: center; justify-content: center; color: var(--muted); font-style: italic; }',
    '    .content { padding: 18px; }',
    '    .meta { margin-top: 6px; color: var(--muted); font-size: 0.95rem; }',
    '    .actions { display: flex; gap: 12px; flex-wrap: wrap; margin-top: 16px; }',
    '    .actions a { text-decoration: none; padding: 10px 14px; border-radius: 999px; background: var(--accent); color: white; }',
    '    .actions a.secondary { background: transparent; color: var(--accent); border: 1px solid var(--accent); }',
    '    pre { white-space: pre-wrap; word-break: break-word; background: #f6faf8; padding: 12px; border-radius: 12px; border: 1px solid var(--line); }',
    '    code { font-family: "Cascadia Code", Consolas, monospace; }',
    '  </style>',
    '</head>',
    '<body>',
    '  <main>',
    '    <h1>VI History review catalog</h1>',
    '    <p class="lead">Immutable VI History review sites prepared for GitHub Pages. Each entry preserves its own publication identity and carries a follow-on epic request stub so humans can pivot from inspection to scoped change intake without hunting for the original run.</p>',
    `    <div class="meta">Catalog entries: ${entries.length}</div>`,
    `    <section class="grid">${cards}</section>`,
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
    description: 'Aggregate multiple VI History Pages publication packages into one catalog site.',
  });

  parser.add_argument('--output-dir', { required: true, help: 'Directory where the combined Pages site should be written.' });
  parser.add_argument('--publication-dir', { action: 'append', required: false, help: 'Directory containing publication.json and a prepared site.' });
  parser.add_argument('--scan-root', { required: false, help: 'Optional root to recursively scan for publication.json files.' });
  parser.add_argument('--pages-base-url', { required: false, help: 'Optional base URL for the deployed Pages site.' });
  parser.add_argument('--catalog-path-root', { required: false, default: 'vi-history-smoke', help: 'Logical root path for catalog publication.' });
  parser.add_argument('--epic-repository', { required: false, default: 'LabVIEW-Community-CI-CD/compare-vi-cli-action', help: 'Repository slug to receive follow-on epic requests.' });
  parser.add_argument('--epic-template', { required: false, default: '02-feature-program-intake.yml', help: 'GitHub issue template filename for epic intake.' });
  parser.add_argument('--epic-label', { action: 'append', required: false, help: 'Epic issue labels. Repeat or use comma-separated values.' });
  parser.add_argument('--step-summary', { required: false, help: 'Optional GitHub Step Summary path to append catalog details to.' });

  const args = parser.parse_args() as Args;
  const outputRoot = ensureDirectory(resolve(process.cwd(), args.output_dir));
  const candidateDirs = [
    ...(args.publication_dir ?? []).map((value) => resolve(process.cwd(), value)),
    ...(args.scan_root ? findPublicationDirs(resolve(process.cwd(), args.scan_root)) : []),
  ];
  const publicationDirs = [...new Set(candidateDirs)].sort((left, right) => left.localeCompare(right));

  if (publicationDirs.length === 0) {
    throw new Error('No publication directories were provided.');
  }

  const epicLabels = normalizeLabels(args.epic_label && args.epic_label.length > 0 ? args.epic_label : ['enhancement', 'program']);
  const baseUrl = args.pages_base_url ? args.pages_base_url.replace(/\/+$/u, '') : null;
  const entries = publicationDirs.map((directoryPath) => {
    const manifestPath = join(directoryPath, 'publication.json');
    if (!existsSync(manifestPath)) {
      throw new Error(`publication.json not found under ${directoryPath}`);
    }

    const publication = publicationSchema.parse(readJson<unknown>(manifestPath));
    const destinationRoot = join(outputRoot, ...publication.publicationPath.split('/'));
    ensureDirectory(dirname(destinationRoot));
    cpSync(directoryPath, destinationRoot, { recursive: true, force: true });

    const heroImagePath = publication.previews.items.length > 0 ? publication.previews.items[0].relativePath : null;
    const siteUrl = baseUrl ? `${baseUrl}/${publication.publicationPath}/index.html` : publication.siteUrl ?? null;
    const epicRequest = buildEpicRequest(publication, args.epic_repository ?? 'LabVIEW-Community-CI-CD/compare-vi-cli-action', args.epic_template ?? '02-feature-program-intake.yml', epicLabels);

    return {
      publicationKey: publication.publicationKey,
      publicationPath: publication.publicationPath,
      siteUrl,
      source: publication.source,
      suite: publication.suite,
      previews: {
        publishedImageCount: publication.previews.publishedImageCount,
        heroImagePath,
      },
      epicRequest,
    };
  }).sort((left, right) => {
    if (left.source.runId !== right.source.runId) {
      return right.source.runId - left.source.runId;
    }
    return right.source.runAttempt - left.source.runAttempt;
  });

  const catalogDigest = sha256Text(stableStringify(entries));
  const catalog = {
    schema: 'vi-history-pages-catalog@v1',
    generatedAt: new Date().toISOString(),
    catalogDigest,
    catalogPathRoot: args.catalog_path_root ?? 'vi-history-smoke',
    pagesBaseUrl: baseUrl,
    entryCount: entries.length,
    entries,
  };

  writeFileSync(join(outputRoot, 'catalog.json'), `${JSON.stringify(catalog, null, 2)}\n`, 'utf8');
  writeFileSync(join(outputRoot, 'index.html'), `${buildCatalogIndex(entries)}\n`, 'utf8');

  if (args.step_summary) {
    appendStepSummary(resolve(process.cwd(), args.step_summary), [
      '### VI History Pages Catalog',
      '',
      `- entries: \`${entries.length}\``,
      `- catalog_digest: \`${catalogDigest}\``,
      `- output_dir: \`${outputRoot}\``,
      ...(baseUrl ? [`- pages_base_url: \`${baseUrl}\``] : []),
    ]);
  }

  // eslint-disable-next-line no-console
  console.log(JSON.stringify({
    schema: 'vi-history-pages-catalog-result@v1',
    outputDir: outputRoot,
    entryCount: entries.length,
    catalogDigest,
  }, null, 2));
}

main();
