import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';

const repoRoot = resolve(import.meta.dirname, '../..');

function writeJson(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

test('builds a static VI history publication site with preview images', () => {
  const tempRoot = mkdtempSync(join(tmpdir(), 'vi-history-pages-'));
  const suiteRoot = join(tempRoot, 'suite-source');
  const targetDir = join(suiteRoot, 'target-a');
  const previewsDir = join(targetDir, 'previews');
  const outputDir = join(tempRoot, 'site');

  try {
    mkdirSync(previewsDir, { recursive: true });
    writeFileSync(
      join(suiteRoot, 'history-report.html'),
      '<html><body><img src="target-a/previews/history-image-000.png" alt="Front panel preview"></body></html>',
      'utf8',
    );
    writeFileSync(join(previewsDir, 'history-image-000.png'), Buffer.from([0x89, 0x50, 0x4e, 0x47]));

    writeJson(join(targetDir, 'vi-history-image-index.json'), {
      schema: 'pr-vi-history-image-index@v1',
      reportPath: join(suiteRoot, 'history-report.html'),
      outputDir: previewsDir,
      sourceImageCount: 1,
      exportedImageCount: 1,
      images: [
        {
          index: 0,
          fileName: 'history-image-000.png',
          savedPath: join(previewsDir, 'history-image-000.png'),
          alt: 'Front panel preview',
          status: 'saved',
        },
      ],
    });

    writeJson(join(suiteRoot, 'manifest.json'), {
      schema: 'vi-compare/history-suite@v1',
      generatedAt: '2026-03-10T00:00:00.000Z',
      targetPath: 'resource/plugins/NIIconEditor/Miscellaneous/Settings Init.vi',
      requestedStartRef: 'HEAD',
      startRef: '72473e85ce593f5a9482272d711bf576a23c61c5',
      endRef: 'cf932117a601f3a819f5e13fdb0131734c2b20d0',
      reportFormat: 'html',
      resultsDir: suiteRoot,
      requestedModes: ['default', 'attributes'],
      executedModes: ['default', 'attributes'],
      modes: [
        {
          name: 'default',
          slug: 'default',
          flags: [],
          manifestPath: join(suiteRoot, 'default', 'manifest.json'),
          resultsDir: join(suiteRoot, 'default'),
          stats: {
            processed: 2,
            diffs: 1,
            signalDiffs: 1,
            noiseCollapsed: 0,
            errors: 0,
            missing: 0,
            categoryCounts: { 'front-panel': 1 },
            bucketCounts: { 'ui-visual': 1 },
          },
          status: 'ok',
        },
      ],
      stats: {
        processed: 2,
        diffs: 1,
        signalDiffs: 1,
        noiseCollapsed: 0,
        errors: 0,
        missing: 0,
        categoryCounts: { 'front-panel': 1 },
        bucketCounts: { 'ui-visual': 1 },
      },
      status: 'ok',
    });

    const result = spawnSync(
      process.execPath,
      [
        'tools/npm/run-script.mjs',
        'history:pages:build',
        '--',
        '--suite',
        join(suiteRoot, 'manifest.json'),
        '--output-dir',
        outputDir,
        '--source-repository',
        'LabVIEW-Community-CI-CD/compare-vi-cli-action',
        '--source-workflow',
        'Smoke VI History',
        '--source-run-id',
        '22924300851',
        '--source-run-attempt',
        '4',
        '--pages-base-url',
        'https://labview-community-ci-cd.github.io/compare-vi-cli-action',
        '--scenario-label',
        'sequential-multi-vi',
      ],
      {
        cwd: repoRoot,
        encoding: 'utf8',
      },
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);

    const publicationPath = join(outputDir, 'publication.json');
    assert.equal(existsSync(publicationPath), true);

    const schemaValidation = spawnSync(
      process.execPath,
      [
        'tools/npm/run-script.mjs',
        'schema:validate',
        '--',
        '--schema',
        'docs/schemas/vi-history-pages-publication-v1.schema.json',
        '--data',
        publicationPath,
      ],
      {
        cwd: repoRoot,
        encoding: 'utf8',
      },
    );

    assert.equal(schemaValidation.status, 0, schemaValidation.stderr || schemaValidation.stdout);

    const publication = JSON.parse(readFileSync(publicationPath, 'utf8'));
    assert.equal(publication.schema, 'vi-history-pages-publication@v1');
    assert.equal(publication.source.repository, 'LabVIEW-Community-CI-CD/compare-vi-cli-action');
    assert.equal(publication.source.runId, 22924300851);
    assert.equal(publication.previews.publishedImageCount, 1);
    assert.match(publication.siteUrl, /vi-history-smoke\/LabVIEW-Community-CI-CD\/compare-vi-cli-action\/.+\/run-22924300851-attempt-4\/index\.html$/);

    const landingPage = readFileSync(join(outputDir, 'index.html'), 'utf8');
    assert.match(landingPage, /Front panel preview/);
    assert.match(landingPage, /suite\/history-report\.html/);
    assert.match(landingPage, /suite\/target-a\/previews\/history-image-000\.png/);

    assert.equal(existsSync(join(outputDir, 'suite', 'history-report.html')), true);
    assert.equal(existsSync(join(outputDir, 'suite', 'target-a', 'previews', 'history-image-000.png')), true);
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
});
