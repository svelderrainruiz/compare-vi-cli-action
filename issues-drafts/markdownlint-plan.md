# Markdownlint & Icon Editor Doc Refinement

## Milestones
1. Catalog current lint tooling (blocking vs non-blocking).
2. Document ICON_EDITOR_PACKAGE.md generation flow and failure modes.
3. Propose consolidation plan for linting and doc stabilization.

## Findings
### Lint Tooling Inventory
- CLI lints run three primary engines: actionlint, markdownlint (strict + optional relaxed), and docs link checker.
- Non-lint guardrails in the same job include tracked build artifact guard, ad-hoc allowlist notification, and environment snapshot generation.
- `markdownlint` runs twice; the relaxed path previously only covered `docs/releases/**`, leaving long-form docs like `docs/TROUBLESHOOTING.md` under strict rules (MD013/MD032).
- Docs link checker writes JSON output to `tests/results/lint/docs-links.json` but still emits error counts in the summary even when marked non-blocking.

### ICON_EDITOR_PACKAGE.md Churn
- `tools/PrePush-Checks.ps1` reruns `Update-IconEditorFixtureReport.ps1`, rewriting `docs/ICON_EDITOR_PACKAGE.md` whenever the fixture manifest hash differs from the committed baseline.
- Regeneration touches hundreds of entries (resource plugins, tests) because the bundled VIP captures the entire resource directory; even unchanged fixtures produce large add/remove sections.
- The Validate pipeline previously regenerated the fixture report in both `lint` and the (now-removed) `icon-editor-build` job, so contributors often see incidental diffs after any `pre-push` run.
- Regeneration only prints a notice (“docs differ”), leaving contributors unsure whether to commit or revert; guidance remains sparse.

#### Recent Validate Runs (last 5) – top markdownlint offenders
- docs/ICON_EDITOR_PACKAGE.md (MD013) – 208 hits across every run (line length, list formatting).
- docs/DEVELOPER_GUIDE.md (MD013, MD007) – 192+ hits; large tables/bullets exceed 120 chars.
- docs/TROUBLESHOOTING.md (MD013, MD032) – recurring line-length and blank-line issues (48 + 32 hits).
- docs/test-requirements/vi-history-reporting.md & docs/investigations/546-* (MD032) – 32 hits each (list spacing).
- Generated `pr-576-body.md` & icon-editor fixture READMEs (MD032/MD022/MD041) – present in every run; candidates for relaxed linting or ignore list.

### Immediate Opportunities
#### Completed tweaks
- Validate now runs relaxed markdownlint over additional docs (`docs/TROUBLESHOOTING.md`, `docs/ICON_EDITOR_PACKAGE.md`, `docs/DEVELOPER_GUIDE.md`, `docs/investigations/**`, `docs/test-requirements/**`, `docs/knowledgebase/**`, and key READMEs).
- Updated the CLI lint composite action to accept multiline relaxed paths and set the docs link checker default to opt-in.
- Added `**/pr-*.md` to `.markdownlintignore` so generated PR bodies no longer fail strict linting.

#### Remaining proposals
- Treat fixture report regeneration as an explicit developer task (e.g., `npm run icon-editor:update-docs`) instead of auto-running during lint.
- Skip fixture doc regeneration during lint when the fixture assets are unchanged; leverage Validate run metadata to short-circuit the rewrite.
- Evaluate whether any remaining long-form docs need targeted MD013/MD032 overrides beyond the expanded relaxed glob coverage.

## Notes
- TODO: quantify how often `docs/TROUBLESHOOTING.md` still fails after the relaxed glob expansion.
- TODO: decide whether the docs link checker stays in CLI lints or moves to a scheduled/non-blocking workflow.
