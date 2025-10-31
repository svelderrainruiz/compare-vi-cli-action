<!-- markdownlint-disable-next-line MD041 -->
# Release v0.5.4 - Summary & Checklist

Summary

- Bucket-aware VI compare summaries  
  `tools/VICategoryBuckets.psm1`, `tools/Summarize-VIStaging.ps1`, `tools/Compare-VIHistory.ps1`, and
  `tools/Render-VIHistoryReport.ps1` now surface Functional behavior / UI & visual / Metadata bucket totals across
  Markdown, HTML, and GitHub outputs so reviewers can triage diffs without downloading artifacts.
- Reporter coverage & docs alignment  
  New unit suites (`tests/VICategoryBuckets.Tests.ps1`, `tests/Render-VIHistoryReport.Tests.ps1`, expanded staging/history
  tests) and updated docs/acceptance checklists keep the new bucket signals under test.

Release Artifacts

- Notes: `RELEASE_NOTES_v0.5.4.md`
- Changelog section: `CHANGELOG.md` (`v0.5.4`)

Validation (must be green)

- [x] Pester (hosted Windows) - `Invoke-PesterTests.ps1`, 2025-10-31.
- [x] Pester (self-hosted, IntegrationMode include) - `Invoke-PesterTests.ps1 -IntegrationMode include`, 2025-10-31.
- [ ] Fixture Drift (Windows/Ubuntu) - TODO.
- [ ] Validate workflow (release/v0.5.4) - run `priority:validate -- --ref release/v0.5.4` and record the run ID.
- [ ] Manual VI Compare refs (`vi-compare-refs.yml`) - ensure artifacts upload for the release branch.
- [ ] Session-index leak report clean - confirm no rogue LabVIEW/LVCompare processes after staging/history runs.

Upgrade Notes

- Downstream automation can now consume `bucket-counts-json` and bucket columns from staging/history reports; update any
  dashboards parsing category-only data to use the new fields.
- Report fixtures and acceptance checklists expect bucket terminology (Functional behavior, UI / visual, Metadata); keep
  new tests in sync when adding fixtures.

Post-Release

- Tag v0.5.4 on `main`.
- Monitor release workflows (`Validate`, `vi-compare-refs`, staging smoke) to ensure bucket totals render as expected.
- Fast-forward `develop` from `release/v0.5.4` (handled via `npm run release:finalize -- 0.5.4`) and track any follow-up
  fixes (fixture drift, additional bucket coverage). 
