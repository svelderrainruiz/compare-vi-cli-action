# Publish smoke VI History suites as GitHub Pages review sites

**Issue:** `#1012`  
**Labels:** enhancement, ci

## Summary

Turn the smoke-generated VI History suite into a static review site package so
humans can inspect preview images and consolidated HTML from a stable URL rather
than from expiring workflow artifacts.

## Why bigger than artifact upload

- GitHub Actions artifacts expire and are awkward to inspect in review loops.
- PR comments can surface a few preview images, but not a durable suite-level
  gallery or an immutable review URL.
- Future epic requests need a reviewable evidence surface that survives beyond
  a single run summary.
- Hosted Ubuntu runners need a publication contract that works the same way as
  local Windows smoke generation.

## Proposed shape

### 1. Build a static publication package

Generate a review site from the history suite bundle:

- copy the suite root unchanged
- preserve `history-report.html`
- preserve all pair reports and `_files/` asset directories
- surface preview images discovered via `vi-history-image-index.json`
- emit a publication manifest (`vi-history-pages-publication@v1`)

### 2. Key the publication by immutable content identity

Do not publish under branch names alone.

- Prefer `sliceDigest` when available from `vi-history-slice@v1`
- Fallback to a derived content digest from the suite manifest and preview files
- Publish under a content-addressed path such as:
  - `vi-history-smoke/<owner>/<repo>/<publicationKey>/run-<id>-attempt-<n>/`

This keeps the reviewer URL stable for the artifact contents, even if the
branch name is reused or the workflow is re-run.

### 3. Add a Pages deployment layer later

The initial work should stop at producing the publication package. A follow-on
trusted workflow can then:

- download the packaged site from the smoke/certification artifact
- upload it with `actions/upload-pages-artifact`
- deploy it with `actions/deploy-pages`
- update an index page of recent smoke publications

This should mirror the thin deployment pattern already used by
`LabVIEW-Community-CI-CD/open-source` in
`.github/workflows/publish-traceability.yml`: tooling prepares the site, the
workflow just publishes the directory.

## Trust boundary

- Only publish from trusted workflows in the canonical repository.
- Never deploy fork PR content directly to GitHub Pages.
- Treat Pages as the human-friendly surface, not the only source of truth.
- Keep the raw suite artifact and publication manifest as the backing evidence.

## Review surface requirements

- Landing page shall link to the copied `history-report.html`
- Landing page shall show a gallery of preview images when image indexes exist
- Publication manifest shall record:
  - source repository/workflow/run identity
  - publication key and digest source
  - suite summary and executed modes
  - published file inventory with hashes
- Publication path shall be deterministic from inputs

## Acceptance criteria

- [ ] A portable builder creates a static review site package from a history
      suite on both Windows and Ubuntu.
- [ ] The package includes a content-addressed publication key, not just a run
      id or branch name.
- [ ] Preview images are rendered on the landing page from the existing image
      index contracts.
- [ ] The publication manifest exposes enough metadata for humans to request a
      new epic against a specific immutable review surface.
- [ ] A later trusted workflow can deploy the prepared package to GitHub Pages
      without changing the builder contract.

## Risks

- GitHub Pages is reviewer-stable, not strictly immutable, unless we treat the
  publication path as append-only and preserve the raw artifact separately.
- Copying full report trees can create large Pages payloads if bundle size is
  not bounded.
- Preview discovery will drift unless publication validation remains aligned
  with `vi-history-image-index.json`.
