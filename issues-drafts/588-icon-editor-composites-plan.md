# Issue 588 – Working Plan

## Context checkpoints
- Validate workflow currently calls PowerShell scripts inline (`Simulate-IconEditorBuild.ps1`, `Stage-BuildArtifacts.ps1`, `Prepare-FixtureViDiffs.ps1`, `Invoke-FixtureViDiffs.ps1`, `Render-ViComparisonReport.ps1`).
- Acceptance includes splitting the flow into smaller composites (prepare fixture, simulate build, stage artifacts, render report, compare, hook parity).
- Composite actions should live under `.github/actions/icon-editor/*` with README snippets + action.yml metadata.

## Implementation outline
1. **Inventory existing steps**  
   - Map workflow commands to logical boundaries (prepare → simulate → stage → compare → report → hook parity tests).  
   - Identify shared environment inputs (results dirs, GH tokens, enable flags).

2. **Create base composites**  
   - `prepare-fixture`: wraps fixture extraction/report generation (likely calling `Update-IconEditorFixtureReport.ps1` or new helper).  
   - `simulate-build`: calls `Simulate-IconEditorBuild.ps1` with parameters, outputs manifest, artifact paths, version info.  
   - `stage-artifacts`: uses `Stage-BuildArtifacts.ps1`, guarantees fixture report preservation.  
   - `render-report`: runs `Render-ViComparisonReport.ps1`.  
   - `prepare-vi-diff` / `invoke-vi-diff`: handle diff request generation and execution.  
   - `hook-parity-tests`: executes `node --test tools/icon-editor/__tests__/*.mjs` for parity verification.

3. **Wire composites into workflows**  
   - Replace inline pwsh steps in `validate.yml` with corresponding `uses: ./.github/actions/icon-editor/...`.  
   - Ensure job outputs remain equivalent (e.g., `vi_diff` step outputs request counts).  
   - Update other workflows (`ci-orchestrated.yml`, smoke, etc.) if they reuse the scripts.

4. **Testing strategy**  
   - Add unit tests for composite metadata using Node script (schema or presence assertions).  
   - Extend Pester coverage where script behaviour changes (e.g., verifying composite entry points pass through parameters).  
   - Run `tools/PrePush-Checks.ps1`, targeted Pester suites, and `priority:validate --allow-fork`.

5. **Documentation**  
   - Update `docs/ICON_EDITOR_PACKAGE.md` + developer guide to reference new composites and usage patterns.  
   - Provide README per composite with inputs/outputs examples.

## Immediate tasks
- [x] Capture the exact arguments & env vars used today; from `validate.yml`:
  - `Simulate-IconEditorBuild.ps1` receives `-FixturePath`, `-ResultsRoot`, `-ExpectedVersion` (object with `major/minor/patch/build/commit`), `-VipDiffOutputDir`, `-VipDiffRequestsPath`; relies on env `ICON_EDITOR_BUILD_MODE`, `ICON_EDITOR_SIMULATION_FIXTURE`, `ICON_EDITOR_ISSUE`, `RESULTS_DIR`.
  - `Invoke-IconEditorBuild.ps1` takes `-Major`, `-Minor`, `-Patch`, `-Build`, `-ResultsRoot`, optional `-RunUnitTests`.
  - `Prepare-FixtureViDiffs.ps1` uses `-ReportPath`, `-BaselineManifestPath`, `-OutputDir`; emits `vi-diff-requests.json`.
  - `Invoke-FixtureViDiffs.ps1` expects `-RequestsPath`, `-CapturesRoot`, `-SummaryPath`, `-TimeoutSeconds`.
  - `Render-ViComparisonReport.ps1` requires `-SummaryPath`, `-OutputPath`.
  - Jobs export outputs (`package_version`, `manifest_path`, `metadata_path`, `build_mode`, diff request counts) and upload artifacts from `$RUNNER_TEMP\icon-editor` plus `tests/results/_agent/icon-editor`.
- [x] Draft composite skeletons (`prepare-fixture`, `simulate-build`, `stage-artifacts`) under `.github/actions/icon-editor/`, wiring inputs/outputs doc strings.
- [x] Define output contracts for remaining composites and document expectations:
  - `prepare-fixture`: confirm `report-json`, `report-markdown`, `manifest-json`, `results-root`.
  - `simulate-build`: ensure outputs include `manifest-path`, `metadata-path`, `package-version`, `vip-diff-root`, `vip-diff-requests-path`.
  - `stage-artifacts`: bucket paths (`packages`, `reports`, `logs`) and JSON summary string.
  - Future composites (compare/report/hook parity) should expose summary/report paths + metadata for uploads.
  - Update developer docs to list these outputs and example usage.
- [ ] Prototype workflow changes locally (swap one job to use the new composite while keeping inline steps as fallback until tests pass). _In progress_: `validate.yml` now routes the simulate path through `./.github/actions/icon-editor/simulate-build`; follow-up to cover staging + compare steps.

## Wiring plan for staging & compare composites
1. **Stage artifacts**
   - Replace the inline staging block with `uses: ./.github/actions/icon-editor/stage-artifacts`.
   - Surface outputs (`packages-path`, `reports-path`, `logs-path`) and feed them to the artifact upload steps.
   - Ensure fixture report preservation is still honoured (composite already copies rather than moves).

2. **VI diff composites**
   - Author composites:
     - `prepare-vi-diff`: wraps `Prepare-FixtureViDiffs.ps1` (inputs: report path, baseline manifest, output dir; outputs: requests path, request count).
     - `invoke-vi-diff`: wraps `Invoke-FixtureViDiffs.ps1` (inputs: requests path, captures root, summary path, timeout; outputs: summary path, captures root).
     - `render-vi-report`: wraps `Render-ViComparisonReport.ps1` (inputs: summary path, output path).
   - Wire these into `icon-editor-build` (simulate path) and `icon-editor-compare` jobs, replacing the current PowerShell blocks.
   - Expose request counts to the lint job outputs and ensure artifact uploads reference composite outputs.

3. **Docs & validation**
   - Update composite READMEs and `docs/ICON_EDITOR_PACKAGE.md` to mention the new actions and usage.
   - Add simple tests (Node snapshot or schema checks) verifying action metadata consistency.
   - Run `tools/PrePush-Checks.ps1` and dispatch Validate in both simulate and real build modes to confirm end-to-end behaviour.
