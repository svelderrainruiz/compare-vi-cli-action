# Compare VI (composite) GitHub Action

[![Validate](https://github.com/svelderrainruiz/compare-vi-cli-action/actions/workflows/validate.yml/badge.svg)](https://github.com/svelderrainruiz/compare-vi-cli-action/actions/workflows/validate.yml)
[![Smoke test](https://github.com/svelderrainruiz/compare-vi-cli-action/actions/workflows/smoke.yml/badge.svg)](https://github.com/svelderrainruiz/compare-vi-cli-action/actions/workflows/smoke.yml)

Diff two LabVIEW `.vi` files using NI LVCompare CLI. Validated with LabVIEW 2025 Q3 on self-hosted Windows runners.

See also: [`CHANGELOG.md`](./CHANGELOG.md) and the release workflow at `.github/workflows/release.yml`.

Requirements

- Self-hosted Windows runner with LabVIEW 2025 Q3 installed and licensed
- `LVCompare.exe` either on `PATH`, provided via `lvComparePath`, or set as `LVCOMPARE_PATH` environment variable

Inputs

- `base` (required): Path to base `.vi`
- `head` (required): Path to head `.vi`
- `lvComparePath` (optional): Full path to `LVCompare.exe` if not on `PATH`
- `lvCompareArgs` (optional): Extra CLI flags for `LVCompare.exe` (space-delimited; quotes supported)
- `fail-on-diff` (optional, default `true`): Fail the job if differences are found
- `working-directory` (optional): Directory to run the command from; relative `base`/`head` are resolved from here

Outputs

- `diff`: `true|false` whether differences were detected (based on exit code mapping 0=no diff, 1=diff)
- `exitCode`: Raw exit code from the CLI
- `cliPath`: Resolved path to the executable
- `command`: The exact command line executed (quoted) for auditing

Usage (self-hosted Windows)

```yaml
jobs:
  compare:
    runs-on: [self-hosted, Windows]
    steps:
      - uses: actions/checkout@v4
      - name: Compare VIs
        id: compare
        uses: svelderrainruiz/compare-vi-cli-action@v0.1.0
        with:
          working-directory: subfolder/with/vis
          base: relative/path/to/base.vi   # resolved from working-directory if set
          head: relative/path/to/head.vi   # resolved from working-directory if set
          # Preferred: LVCOMPARE_PATH on runner, or provide full path
          lvComparePath: C:\\Program Files\\NI\\LabVIEW 2025\\LVCompare.exe
          # Optional extra flags (space-delimited, quotes supported)
          lvCompareArgs: "--some-flag --value \"C:\\Temp\\My Folder\\file.txt\""
          # Built-in policy: fail on diff by default
          fail-on-diff: "true"

      - name: Act on result
        if: steps.compare.outputs.diff == 'true'
        shell: pwsh
        run: |
          Write-Host 'Differences detected.'
```

Full flag pass-through

- All LVCompare CLI flags are passed via `lvCompareArgs` without opinionated defaults.
- Quoted arguments with spaces are supported: e.g., `--out "C:\\path with spaces\\report.html"`.
- If your organization relies on a common set of flags, define them in your workflow rather than baking them into the action.

Smoke test workflow

- A manual workflow is provided at `.github/workflows/smoke.yml`.
- Trigger it with “Run workflow” and supply `base`, `head`, and optional `lvComparePath`/`lvCompareArgs`.
- It runs the local action (`uses: ./`) on a self-hosted Windows runner and prints outputs.

Notes

- This action maps `LVCompare.exe` exit codes to a boolean `diff` (0 = no diff, 1 = diff). Any other exit code fails the step.
- If you rely on specific report-generation flags, pass them via `lvCompareArgs` and document them in your workflow for your environment.
- Typical locations to try for 2025 Q3 include:
  - `C:\Program Files\NI\LabVIEW 2025\LVCompare.exe`
  - `C:\Program Files\National Instruments\LabVIEW 2025\LVCompare.exe`

Troubleshooting

- Ensure the runner user has the necessary LabVIEW licensing.
- Verify `LVCompare.exe` is reachable (PATH, `LVCOMPARE_PATH`, or `lvComparePath`).
- Check composite action outputs (`diff`, `exitCode`, `cliPath`, `command`) and the CLI exit code for diagnostics.
