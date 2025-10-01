## Copilot Action Guide (Concise)

Model preference: Use Claude Sonnet 4 by default; if unavailable, request an explicit fallback.

### 1. Purpose & Architecture
- Composite GitHub Action invoking NI LVCompare to diff two LabVIEW `.vi` files (LabVIEW 2025 Q3, self‑hosted Windows only).
- Core logic: `scripts/CompareVI.ps1` (functions `Resolve-Cli`, `Invoke-CompareVI`, `Quote`).
- HTML artifact helper: `scripts/Render-CompareReport.ps1` (post-processes executed command & exit code; no direct LVCompare parsing).

### 2. Canonical Path Enforcement (Critical Contract)
- Only accepted LVCompare path: `C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe`.
- Any `lvComparePath` / `LVCOMPARE_PATH` NOT resolving exactly to that path must throw (tests rely on this). Do NOT relax.

### 3. Invocation & Outputs
- Tokenization of `lvCompareArgs` uses regex: `"[^"]+"|\S+` — preserve exactly for round‑trip fidelity.
- Exit codes: 0 => no diff (`diff=false`), 1 => diff (`diff=true`), other => failure (still emit outputs with `diff=false` then throw).
- Always emit (`exitCode`, `cliPath`, `command`, `diff`) BEFORE any throw (see unit tests asserting this behavior).
- Step summary markdown section header: `### Compare VI` with key/value lines (keep naming to avoid downstream parsing breakage).

### 4. Fail-on-diff Semantics
- `fail-on-diff=true` converts a legitimate diff (exit 1) into an error AFTER outputs + summary are written.
- Internal decision variable: `$FailOnDiff`; do not short‑circuit earlier.

### 5. Path & Working Directory Rules
- Relative `base` / `head` resolved after optional `Push-Location` to `working-directory`; return via `Pop-Location` in `finally`.
- Convert resolved file paths to absolute before building command (tests compare abs paths).

### 6. Testing Patterns
- Unit tests in `tests/CompareVI.Tests.ps1` inject a mock executor (`-Executor`) and Pester `Mock Resolve-Cli` to bypass real binary.
- Canonical path policy coverage: `Describe 'Resolve-Cli canonical path enforcement'` — keep error messages containing the word `canonical`.
- Integration tests (`tests/CompareVI.Integration.Tests.ps1`) expect real CLI and environment vars: `LV_BASE_VI`, `LV_HEAD_VI`.
- HTML report generation validated via `Render-CompareReport.ps1` and optional `LabVIEWCLI` section (skip logic used—retain tag names & conditions).

### 7. HTML Report Helper
- Does not invoke LVCompare; it reconstructs Base/Head from the executed command if not supplied; keep tokenizer pattern identical to main script for consistency.

### 8. Modification Guardrails (What NOT to change)
- Do NOT: alter canonical path, change tokenization regex, rename output keys, reorder summary lines materially, or swallow exceptions before outputs.
- Keep `diff` output lowercase `true|false`.

### 9. Extension Guidance
- To add new flags: rely on pass‑through `lvCompareArgs`; do not introduce bespoke input unless essential and test-covered.
- If adding new outputs, append (don’t rename existing) and update summary + tests in a single commit.

### 10. Key Files Quick Map
- `action.yml` – wiring & output plumbing.
- `scripts/CompareVI.ps1` – core compare logic.
- `scripts/Render-CompareReport.ps1` – HTML summary.
- `tests/*` – unit vs integration separation; study for behavioral contracts.
- `docs/knowledgebase/*` – authoritative flag recipes (noise filters: `-nobdcosm -nofppos -noattr`).

### 11. Common Local Commands
Run unit tests (no real CLI): `pwsh -File ./tools/Run-Pester.ps1`
Run all (needs real CLI & env): `pwsh ./Invoke-PesterTests.ps1 -IncludeIntegration true`

### 12. Release Invariants
- Keep changelog headings format: `## [vX.Y.Z] - YYYY-MM-DD` (release workflow parses this).
- Release must be deterministic: tag `vX.Y.Z` corresponds exactly to committed `action.yml` + scripts; never rewrite tags. Re-run of release workflow under identical repo state must produce byte-identical packaged artifact & notes (verify by diffing generated release body against changelog section).
 - See Section 18 for verification checklist & automation snippet.

Questions when updating? Validate with unit tests first—if they fail you likely changed a contract above.

### 13. Gotchas & Quoting Nuances
- YAML backslashes: In workflow `with:` blocks double-escape Windows paths (`C:\\Program Files\\...`) only when YAML + string interpolation requires; single backslashes are fine in plain strings but safer to double in examples.
- `lvCompareArgs` parsing: Regex is literal `"[^"]+"|\S+`; keep quotes around paths with spaces. Inner quotes must not be smart quotes.
- Avoid adding trailing spaces inside quotes (would become part of token after `.Trim('"')`).
- Summary order: The markdown list under `### Compare VI` must retain key ordering (tests assume pattern; adding new lines append after existing keys).
- Executor tests: Unit tests mock `Resolve-Cli`; don’t rely on actual file presence when adding logic before that mock.
- Canonical path errors MUST include the word `canonical` (Pester assertion uses wildcard match).
- HTML report tokenizer must stay identical to main script for consistent Base/Head reconstruction.
- When adding flags examples, prefer noise filter trio `-nobdcosm -nofppos -noattr` as canonical pattern (mirrors tests + knowledgebase).

### 14. HTML Report Artifact Publishing
	1. Run compare action (captures outputs).
	2. Always run renderer (use `if: always()`) so failed comparisons (unknown exit code) still produce a report.
	3. Upload artifact (HTML file) for review.
	```yaml
	- name: Compare VIs
		id: compare
		uses: LabVIEW-Community-CI-CD/compare-vi-cli-action@vX.Y.Z
		with:
			base: path/to/base.vi
			head: path/to/head.vi
			lvCompareArgs: -nobdcosm -nofppos -noattr
	- name: Render HTML report
		if: always()
		shell: pwsh
		run: |
			$html = Join-Path $env:RUNNER_TEMP 'compare-report.html'
			pwsh -File scripts/Render-CompareReport.ps1 `
				-Command '${{ steps.compare.outputs.command }}' `
				-ExitCode [int]'${{ steps.compare.outputs.exitCode }}' `
				-Diff '${{ steps.compare.outputs.diff }}' `
				-CliPath '${{ steps.compare.outputs.cliPath }}' `
				-OutputPath $html
			"htmlPath=$html" >> $env:GITHUB_OUTPUT
	- name: Upload comparison report
		if: always()
		uses: actions/upload-artifact@v4
		with:
			name: lvcompare-report
			path: ${{ runner.temp }}/compare-report.html
	```
	- If action exits with unknown code, renderer still marks Diff=false unless outputs said otherwise.
	- Don’t attempt to derive semantic diff content; renderer is intentionally metadata-only.
	- If adding new outputs needed in report, append (do not rename) and pass through explicitly.
- PR ergonomics: Link artifact in PR comment or use summary line referencing the artifact name for discoverability.
### 15. Potential Future Enhancements (Backlog – keep contracts intact)
Non-breaking ideas (add tests alongside implementation):
- Append new output: `baseHash` / `headHash` (e.g., SHA256 of files) for cache keys & integrity; compute after path resolution, before execution.
- Optional `hash-algorithm` input (default SHA256) only if hash outputs added.
- Add `--` passthrough sentinel support if LVCompare ever collides with future action inputs.
- Emit JSON metadata artifact (mirror step summary) to ease downstream automation.
- Add `diffStatus` output enumerating `no-diff|diff|error` (append only; retain `diff`).
- Support auto HTML report generation via boolean input (internally call renderer) while keeping current external pattern.
- Provide opt-in soft-warning mode instead of failure for unknown exit codes (append `warning=true`).
- Embed command + exit metadata inside HTML as `<meta>` tags for machine parsing.
- Add a minimal PowerShell module wrapper (`CompareVI.ActionTools.psm1`) exposing `Invoke-CompareVI` for external reuse.
- Introduce `diagnostics` verbosity flag to log tokenization decisions (unit tests assert presence when enabled).
Guardrails when implementing:
- Never mutate existing output names or change canonical path / regex.
- Append new markdown lines after existing ordered block under `### Compare VI`.
- Extend tests first: unit (mock executor) + integration (when applicable).

### 16. Test Dispatcher & Env Var Nuances
- Entrypoints:
	- `Invoke-PesterTests.ps1` (root): self-hosted workflow mirror; assumes Pester present; rich formatting & parameters.
	- `tools/Run-Pester.ps1`: lightweight dev helper; auto-installs Pester; faster loop for unit tests.
- Tag behavior: Integration tests excluded unless `-IncludeIntegration true` (or equivalent switch) provided.
- Integration prerequisites: `LV_BASE_VI`, `LV_HEAD_VI` (distinct `.vi` paths) + canonical LVCompare path installed.
- Skip logic: Integration tests contain `-Skip:` guards for missing CLI / LabVIEWCLI—retain when expanding.
- Dispatcher outputs: `tests/results/pester-results.xml` (NUnit) + `tests/results/pester-summary.txt`; preserve names if post-processing.
- Typical commands:
	- Unit only: `pwsh -File ./Invoke-PesterTests.ps1`
	- With integration: `pwsh -File ./Invoke-PesterTests.ps1 -IncludeIntegration true`
- Env var example:
	```powershell
	$env:LV_BASE_VI='C:\TestVIs\Base.vi'
	$env:LV_HEAD_VI='C:\TestVIs\Modified.vi'
	pwsh -File ./Invoke-PesterTests.ps1 -IncludeIntegration true
	```
- Add new test category? Prefer new tag (e.g. `Performance`) + extend filtering rather than bespoke script branching.
- Maintain exit code semantics (0 pass / 1 failure) to keep CI logic stable.

### 17. Decision Tree: Adding Inputs / Outputs Safely
1. Can desired behavior be expressed via existing `lvCompareArgs`? If yes: document a recipe; stop.
2. Is feature derivable from existing inputs (pure function)? Add only a new output; no input.
3. Need new input? Ensure name does not collide with: `base, head, lvComparePath, lvCompareArgs, fail-on-diff, working-directory`.
4. Will it alter LVCompare invocation? Ensure pass-through (never mutate user-provided token order); add unit tests around tokenization.
5. Outputs: append only. Update `action.yml`, step summary (append lines), renderer (if surfaced), tests.
6. Error/edge handling: Preserve existing exit code mapping & diff logic; new logic must not swallow exceptions before outputs.
7. Docs: Update `README.md` (Inputs/Outputs), this file (append section), and add minimal usage snippet.
8. Validation checklist before merge:
	 - Canonical path constant unchanged.
	 - Tokenization regex unchanged.
	 - Existing summary lines byte-for-byte identical (new lines only appended).
	 - `diff` semantics (exit 0/1) untouched.
	 - New tests cover: unit diff/no-diff/error paths + any new branching.
	 - Optional: integration test only if relies on real CLI state.
If any item fails → open design discussion instead of merging.

### 18. Deterministic Release Verification
Objective: Ensure running the release workflow multiple times for the same commit/tag yields identical artifacts & release notes.

Checklist BEFORE tagging:
1. Working tree clean (`git status` no changes).
2. `CHANGELOG.md` contains upcoming section with correct heading (`## [vX.Y.Z] - YYYY-MM-DD`).
3. Version references updated (README usage badge/tag, marketplace examples) — no stale tag strings.
4. No generated files (e.g., cached test results) tracked that could vary run-to-run.
5. PowerShell scripts have consistent line endings (CRLF or LF) — avoid mixed endings.
6. Run unit tests locally (`pwsh -File ./tools/Run-Pester.ps1`) -> exit 0.
7. (If applicable) integration tests pass on self-hosted runner.
8. Diff of prospective release notes vs changelog section is empty (automation below).

Post-tag reproducibility steps:
1. Fetch tag in a clean clone.
2. Re-run release workflow (dry-run or manual dispatch) with same inputs.
3. Compare generated release body text to changelog slice (exact match, including whitespace).
4. (Optional) Hash critical files and compare:
	 - `Get-FileHash action.yml`, `Get-FileHash scripts/CompareVI.ps1`, `Get-FileHash scripts/Render-CompareReport.ps1`.

Automation snippet (PowerShell) to extract changelog section & diff against prepared release notes file `dist/release-body.md`:
```powershell
$version = 'vX.Y.Z'
$changelog = Get-Content CHANGELOG.md -Raw
$pattern = "## \[$([regex]::Escape($version))\] - .*?$(?=\n## \[v|\Z)"
$section = [regex]::Match($changelog, $pattern, 'Singleline').Value.Trim()
if (-not $section) { throw "Changelog section for $version not found" }
New-Item -ItemType Directory -Path dist -Force | Out-Null
$releaseBodyPath = 'dist/release-body.md'
if (-not (Test-Path $releaseBodyPath)) { throw 'Expected generated release body missing: dist/release-body.md' }
$generated = Get-Content $releaseBodyPath -Raw
if ($generated.Trim() -ne $section) {
	Write-Host 'Release body mismatch vs changelog section:' -ForegroundColor Red
	$tempA = New-TemporaryFile; $tempB = New-TemporaryFile
	$section | Out-File $tempA -Encoding utf8
	$generated | Out-File $tempB -Encoding utf8
	git --no-pager diff --no-index $tempA $tempB
	throw 'Determinism check failed'
} else {
	Write-Host 'Determinism check passed (release body == changelog section).' -ForegroundColor Green
}
```

Optional artifact hashing (add to release job prior to publish):
```powershell
$critical = 'action.yml','scripts/CompareVI.ps1','scripts/Render-CompareReport.ps1'
$hashes = foreach ($f in $critical) { (Get-FileHash $f -Algorithm SHA256 | Select-Object Path, Hash) }
$hashes | ForEach-Object { "${_.Path}: ${_.Hash}" }
$hashes | ConvertTo-Json -Depth 3 | Out-File dist/file-hashes.json -Encoding utf8
```

Store `file-hashes.json` as part of the release assets; future audits can re-hash and compare for integrity.
