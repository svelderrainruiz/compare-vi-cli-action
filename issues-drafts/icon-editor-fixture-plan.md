# Icon Editor Fixture Baseline – Reproducibility Notes

## Goals
1. Replace the manually supplied fixture bundle with a reproducible baseline generated from our build scripts.
2. Ensure `docs/ICON_EDITOR_PACKAGE.md`, `fixture-report.json/md`, and manifest hashes stay in sync with that baseline.

## Current State Investigation
- [ ] **Inventory fixture assets**  
  - [ ] List contents of `tests/fixtures/icon-editor/` (VIPs, LVLIBPs, manifest JSON).  
  - [ ] Capture how `fixture-manifest.json` describes those assets (hashes, categories).
- [ ] **Trace `Update-IconEditorFixtureReport.ps1`**  
  - [ ] Understand inputs (fixture directory, manifest) and generated outputs (`fixture-report.json`, `fixture-report.md`, `docs/ICON_EDITOR_PACKAGE.md`).  
  - [ ] Note any cleanup/reset steps (e.g., Git checkout behaviour).
- [ ] **Review validation hooks**  
  - [ ] Examine `tools/PrePush-Checks.ps1` fixture check.  
  - [ ] Inspect `tools/icon-editor/__tests__/fixture-hashes.test.mjs` and related tests.
- [ ] **Identify reproducible source**  
  - [ ] Determine which build scripts (`Simulate-IconEditorBuild.ps1`, replay helpers) can emit the canonical VIP/LVLIBP bundle.  
  - [ ] Document gaps preventing automated regeneration today.

## Next Actions
1. Complete the inventory of the existing fixture assets and log findings here.  
2. Walk the `Update-IconEditorFixtureReport.ps1` flow end-to-end and record the pipeline stages.  
3. Draft a proposal for producing the fixture bundle via the replay/build scripts (inputs, commands, expected outputs).
