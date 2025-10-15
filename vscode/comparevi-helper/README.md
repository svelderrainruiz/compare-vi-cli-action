# CompareVI Helper (Local Dev Extension)

This lightweight extension adds a command to run LVCompare against two VIs in this repo, with quick year/bitness selection.

## Commands

- CompareVI: Run Manual Compare (`comparevi.runManualCompare`)
  - Prompts for LabVIEW year and bitness
  - Calls `tools/Invoke-LVCompare.ps1` with the resolved LabVIEW path
  - Uses workspace defaults for Base/Head VIs and output folder
  - Offers an optional multi-select picker for LVCompare flags (configurable)

- CompareVI: Run Profile (`comparevi.runProfile`)
  - Reads profiles from `tools/comparevi.profiles.json` (configurable via `comparevi.profilesPath`)
  - Lets you pick a named profile and runs it

- CompareVI: Compare Active VI with Previous Commit (`comparevi.compareActiveWithPrevious`)
  - Compares the currently open `.vi` against `HEAD~1` for the same path
  - Extracts both revisions to temporary files and runs LVCompare
  - Reuses the same output directory and summary/flag behavior as other commands

- CompareVI: Open/Create Profiles (`comparevi.openProfiles`)
  - Opens the profiles file; creates a sample if missing

## Settings

- `comparevi.labview.year` (default `2025`)
- `comparevi.labview.bits` (default `64`)
- `comparevi.paths.baseVi` (default `${workspaceFolder}/VI2.vi`)
- `comparevi.paths.headVi` (default `${workspaceFolder}/tmp-commit-236ffab/VI2.vi`)
- `comparevi.output.dir` (default `tests/results/manual-vi2-compare`)
- `comparevi.profilesPath` (default `tools/comparevi.profiles.json`)
- `comparevi.passFlags` (default `false`) — pass profile/default flags without prompting
- `comparevi.showFlagPicker` (default `true`) — prompt for flags with a multi-select picker before each run
- `comparevi.knownFlags` — list of LVCompare flags shown in the picker
- `comparevi.showSourcePicker` (default `true`) — prompt for base/head commit sources when profiles define commit refs
- `comparevi.keepTempVi` (default `false`) — retain extracted temporary VIs after each run (handy for debugging)

## Commit-Based Sources

Profiles can describe comparisons entirely in terms of Git commits. Example:

```json
{
  "name": "Compare VI2",
  "year": "2025",
  "bits": "64",
  "vis": [
    { "id": "root", "ref": "HEAD", "path": "VI2.vi" },
    { "id": "previous", "ref": "HEAD~1", "path": "VI2.vi" }
  ],
  "defaultBase": "previous",
  "defaultHead": "root"
}
```

On each run the extension extracts the selected commits to a temporary directory (`base.vi` / `head.vi`), renames them to avoid collisions, and feeds them to `Invoke-LVCompare.ps1`. QuickPick prompts show commit hashes and subjects, and the post-run summary lists the chosen refs and VI paths.

The CompareVI Manual side bar (Activity Bar → CompareVI Manual) lists profiles and their current selections. Right-click a profile to run it, choose new base/head commits, or open the latest capture/report.

- Paths in `vis` entries are relative to the repository. If omitted, the extension will list `.vi` files in the commit and prompt you to choose one.
- Temporary files are cleaned up automatically unless `comparevi.keepTempVi` is enabled.
- Tree view vignettes display the current commit selections; context menus still provide “Run”, “Open Report”, etc.

## Run locally

1. Open this repository in VS Code.
2. Press F5 (or run the “Run Extension” launch config) to start an Extension Development Host.
3. Open the Command Palette and run “CompareVI: Run Manual Compare”.

The command opens an Integrated Terminal and executes the PowerShell script.

## Tasks (TaskProvider)

The extension registers a `comparevi` task type that surfaces one VS Code task per profile.

- Open the Task Runner (Terminal → Run Task) and look for tasks named `CompareVI: <profile name>`.
- Running a task executes `pwsh -File tools/Invoke-LVCompare.ps1` populated from the profile.

## Package the extension (VSIX)

From the repository root:

```bash
npm install --prefix vscode/comparevi-helper
npm run package --prefix vscode/comparevi-helper
```

The VSIX (`comparevi-helper-<version>.vsix`) is emitted in `vscode/comparevi-helper/` and can be installed via
`code --install-extension <path-to-vsix>`.

## Testing

- Unit tests (Vitest): `npm run test:unit`
- Integration tests (VS Code host): `npm run test:ext`
- Full test suite: `npm test`
