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

function makePublicationDir(root, publicationPath, publicationKey, runId, targetPath, previewName) {
  const publicationDir = join(root, publicationKey);
  mkdirSync(join(publicationDir, 'suite', 'previews'), { recursive: true });
  writeFileSync(join(publicationDir, 'index.html'), `<html><body>${targetPath}</body></html>`, 'utf8');
  writeFileSync(join(publicationDir, 'suite', 'history-report.html'), `<html><body>${targetPath}</body></html>`, 'utf8');
  writeFileSync(join(publicationDir, 'suite', 'previews', previewName), 'preview', 'utf8');
  writeJson(join(publicationDir, 'publication.json'), {
    schema: 'vi-history-pages-publication@v1',
    generatedAt: '2026-03-11T00:30:00.000Z',
    publicationKey,
    digestSource: 'derived',
    publicationPath,
    siteUrl: `https://labview-community-ci-cd.github.io/compare-vi-cli-action/${publicationPath}/index.html`,
    pagesBaseUrl: 'https://labview-community-ci-cd.github.io/compare-vi-cli-action',
    scenarioLabel: 'sequential',
    source: {
      repository: 'LabVIEW-Community-CI-CD/compare-vi-cli-action',
      workflow: 'Smoke VI History',
      runId,
      runAttempt: 1,
    },
    suite: {
      schema: 'vi-compare/history-suite@v1',
      targetPath,
      requestedStartRef: 'HEAD',
      startRef: 'abc123',
      endRef: 'def456',
      requestedModes: ['default'],
      executedModes: ['default'],
      reportFormat: 'html',
      status: 'ok',
      historyReportPath: 'suite/history-report.html',
      stats: {
        processed: 1,
        diffs: 1,
        signalDiffs: 1,
        noiseCollapsed: 0,
        errors: 0,
        missing: 0,
        categoryCounts: { 'front-panel': 1 },
        bucketCounts: { 'ui-visual': 1 },
      },
    },
    previews: {
      imageIndexCount: 1,
      publishedImageCount: 1,
      missingImageCount: 0,
      items: [
        {
          relativePath: `suite/previews/${previewName}`,
          alt: `${targetPath} preview`,
          sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          byteLength: 7,
          sourceIndexPath: 'suite/vi-history-image-index.json',
          imageOrdinal: 0,
        },
      ],
    },
    files: [
      {
        relativePath: 'index.html',
        kind: 'landing-page',
        sha256: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        byteLength: 20,
      },
    ],
    status: 'prepared',
  });
  return publicationDir;
}

test('builds a catalog site from multiple publication directories', () => {
  const tempRoot = mkdtempSync(join(tmpdir(), 'vi-history-pages-catalog-'));
  const publicationsRoot = join(tempRoot, 'publications');
  const outputDir = join(tempRoot, 'catalog-site');

  try {
    mkdirSync(publicationsRoot, { recursive: true });
    makePublicationDir(
      publicationsRoot,
      'vi-history-smoke/LabVIEW-Community-CI-CD/compare-vi-cli-action/pub-one/run-200-attempt-1',
      'pub-one',
      200,
      'fixtures/vi-stage/control-rename/Head.vi',
      'control.png',
    );
    makePublicationDir(
      publicationsRoot,
      'vi-history-smoke/LabVIEW-Community-CI-CD/compare-vi-cli-action/pub-two/run-201-attempt-1',
      'pub-two',
      201,
      'fixtures/vi-stage/bd-cosmetic/Head.vi',
      'diagram.png',
    );

    const result = spawnSync(
      process.execPath,
      [
        'tools/npm/run-script.mjs',
        'history:pages:catalog',
        '--',
        '--scan-root',
        publicationsRoot,
        '--output-dir',
        outputDir,
        '--pages-base-url',
        'https://labview-community-ci-cd.github.io/compare-vi-cli-action',
      ],
      {
        cwd: repoRoot,
        encoding: 'utf8',
      },
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);

    const catalogPath = join(outputDir, 'catalog.json');
    assert.equal(existsSync(catalogPath), true);

    const schemaValidation = spawnSync(
      process.execPath,
      [
        'tools/npm/run-script.mjs',
        'schema:validate',
        '--',
        '--schema',
        'docs/schemas/vi-history-pages-catalog-v1.schema.json',
        '--data',
        catalogPath,
      ],
      {
        cwd: repoRoot,
        encoding: 'utf8',
      },
    );

    assert.equal(schemaValidation.status, 0, schemaValidation.stderr || schemaValidation.stdout);

    const catalog = JSON.parse(readFileSync(catalogPath, 'utf8'));
    assert.equal(catalog.schema, 'vi-history-pages-catalog@v1');
    assert.equal(catalog.entryCount, 2);
    assert.equal(catalog.entries[0].source.runId, 201);
    assert.match(catalog.entries[0].epicRequest.issueUrl, /issues\/new\?/);
    assert.match(catalog.entries[0].epicRequest.issueUrl, /template=02-feature-program-intake\.yml/);

    const landingPage = readFileSync(join(outputDir, 'index.html'), 'utf8');
    assert.match(landingPage, /VI History review catalog/);
    assert.match(landingPage, /Request new epic/);
    assert.match(landingPage, /fixtures\/vi-stage\/bd-cosmetic\/Head\.vi/);

    assert.equal(
      existsSync(join(outputDir, 'vi-history-smoke', 'LabVIEW-Community-CI-CD', 'compare-vi-cli-action', 'pub-two', 'run-201-attempt-1', 'index.html')),
      true,
    );
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
});
