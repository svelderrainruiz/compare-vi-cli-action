import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { createServer } from 'node:http';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { spawn, spawnSync } from 'node:child_process';

const repoRoot = resolve(import.meta.dirname, '../..');

function writeJson(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function spawnNodeAsync(args, options = {}) {
  return new Promise((resolvePromise, rejectPromise) => {
    const child = spawn(process.execPath, args, {
      cwd: repoRoot,
      stdio: ['ignore', 'pipe', 'pipe'],
      ...options,
    });

    let stdout = '';
    let stderr = '';

    child.stdout?.on('data', (chunk) => {
      stdout += chunk.toString();
    });

    child.stderr?.on('data', (chunk) => {
      stderr += chunk.toString();
    });

    child.on('error', rejectPromise);
    child.on('close', (code, signal) => {
      resolvePromise({ code, signal, stdout, stderr });
    });
  });
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

test('hydrates an existing published catalog before merging new publications', async () => {
  const tempRoot = mkdtempSync(join(tmpdir(), 'vi-history-pages-catalog-hydrate-'));
  const existingRoot = join(tempRoot, 'existing-site');
  const newPublicationsRoot = join(tempRoot, 'new-publications');
  const outputDir = join(tempRoot, 'catalog-site');

  let server;
  try {
    mkdirSync(existingRoot, { recursive: true });
    mkdirSync(newPublicationsRoot, { recursive: true });

    const existingPublicationPath = 'vi-history-smoke/LabVIEW-Community-CI-CD/compare-vi-cli-action/existing-one/run-150-attempt-1';
    const existingPublicationRoot = join(existingRoot, ...existingPublicationPath.split('/'));
    mkdirSync(join(existingPublicationRoot, 'suite', 'previews'), { recursive: true });
    writeFileSync(join(existingPublicationRoot, 'index.html'), '<html><body>existing</body></html>', 'utf8');
    writeFileSync(join(existingPublicationRoot, 'suite', 'history-report.html'), '<html><body>existing-history</body></html>', 'utf8');
    writeFileSync(join(existingPublicationRoot, 'suite', 'previews', 'existing.png'), 'old-preview', 'utf8');
    writeJson(join(existingPublicationRoot, 'publication.json'), {
      schema: 'vi-history-pages-publication@v1',
      generatedAt: '2026-03-11T00:50:00.000Z',
      publicationKey: 'existing-one',
      digestSource: 'derived',
      publicationPath: existingPublicationPath,
      siteUrl: `http://127.0.0.1/site/${existingPublicationPath}/index.html`,
      pagesBaseUrl: 'http://127.0.0.1/site',
      scenarioLabel: 'attribute',
      source: {
        repository: 'LabVIEW-Community-CI-CD/compare-vi-cli-action',
        workflow: 'Smoke VI History',
        runId: 150,
        runAttempt: 1,
      },
      suite: {
        schema: 'vi-compare/history-suite@v1',
        targetPath: 'fixtures/vi-attr/Head.vi',
        requestedStartRef: 'HEAD',
        startRef: 'old-ref',
        endRef: 'old-end',
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
          categoryCounts: { attribute: 1 },
          bucketCounts: { metadata: 1 },
        },
      },
      previews: {
        imageIndexCount: 1,
        publishedImageCount: 1,
        missingImageCount: 0,
        items: [
          {
            relativePath: 'suite/previews/existing.png',
            alt: 'existing preview',
            sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            byteLength: 11,
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
        {
          relativePath: 'suite/history-report.html',
          kind: 'history-report',
          sha256: 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
          byteLength: 32,
        },
        {
          relativePath: 'suite/previews/existing.png',
          kind: 'preview-image',
          sha256: 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
          byteLength: 11,
        },
      ],
      status: 'prepared',
    });

    writeJson(join(existingRoot, 'catalog.json'), {
      schema: 'vi-history-pages-catalog@v1',
      generatedAt: '2026-03-11T00:50:00.000Z',
      catalogDigest: 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
      catalogPathRoot: 'vi-history-smoke',
      pagesBaseUrl: 'http://127.0.0.1/site',
      entryCount: 1,
      entries: [
        {
          publicationKey: 'existing-one',
          publicationPath: existingPublicationPath,
          siteUrl: `http://127.0.0.1/site/${existingPublicationPath}/index.html`,
          source: {
            repository: 'LabVIEW-Community-CI-CD/compare-vi-cli-action',
            workflow: 'Smoke VI History',
            runId: 150,
            runAttempt: 1,
          },
          suite: {
            targetPath: 'fixtures/vi-attr/Head.vi',
            startRef: 'old-ref',
            status: 'ok',
            executedModes: ['default'],
            historyReportPath: 'suite/history-report.html',
          },
          previews: {
            publishedImageCount: 1,
            heroImagePath: 'suite/previews/existing.png',
          },
          epicRequest: {
            repository: 'LabVIEW-Community-CI-CD/compare-vi-cli-action',
            template: '02-feature-program-intake.yml',
            labels: ['enhancement'],
            title: 'placeholder',
            issueUrl: 'https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/issues/new',
            bodyLines: [],
          },
        },
      ],
    });

    const newPublicationDir = makePublicationDir(
      newPublicationsRoot,
      'vi-history-smoke/LabVIEW-Community-CI-CD/compare-vi-cli-action/new-one/run-250-attempt-1',
      'new-one',
      250,
      'fixtures/vi-stage/front-panel/Head.vi',
      'front-panel.png',
    );

    server = createServer((request, response) => {
      const requestUrl = new URL(request.url, 'http://127.0.0.1');
      const relativePath = requestUrl.pathname.replace(/^\/site\/?/u, '');
      const targetPath = join(existingRoot, ...relativePath.split('/').filter((segment) => segment.length > 0));
      if (!existsSync(targetPath)) {
        response.statusCode = 404;
        response.end('not found');
        return;
      }

      response.statusCode = 200;
      response.end(readFileSync(targetPath));
    });

    await new Promise((resolveServer) => server.listen(0, '127.0.0.1', resolveServer));
    const address = server.address();
    const baseUrl = `http://127.0.0.1:${address.port}/site`;

    const result = await spawnNodeAsync(
      [
        'tools/npm/run-script.mjs',
        'history:pages:catalog',
        '--',
        '--publication-dir',
        newPublicationDir,
        '--output-dir',
        outputDir,
        '--pages-base-url',
        baseUrl,
        '--existing-catalog-url',
        `${baseUrl}/catalog.json`,
      ],
      {
        encoding: 'utf8',
      },
    );

    assert.equal(result.code, 0, result.stderr || result.stdout);

    const catalog = JSON.parse(readFileSync(join(outputDir, 'catalog.json'), 'utf8'));
    assert.equal(catalog.entryCount, 2);
    assert.equal(catalog.entries[0].source.runId, 250);
    assert.equal(catalog.entries[1].source.runId, 150);
    assert.equal(
      existsSync(join(outputDir, ...existingPublicationPath.split('/'), 'suite', 'previews', 'existing.png')),
      true,
    );
  } finally {
    if (server) {
      await new Promise((resolveServer, rejectServer) => server.close((error) => (error ? rejectServer(error) : resolveServer())));
    }
    rmSync(tempRoot, { recursive: true, force: true });
  }
});
