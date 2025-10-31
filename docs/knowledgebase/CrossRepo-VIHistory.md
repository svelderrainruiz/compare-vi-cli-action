<!-- markdownlint-disable-next-line MD041 -->
# Cross-Repo VI History Capture

This note records the steps I took to exercise the Compare-VIHistory tooling
against an external repository (`LabVIEW-Community-CI-CD/labview-icon-editor`,
standing issue #527).

## Prerequisites

- Git history with the target VI available locally.
- LVCompare/LabVIEW installed (the same requirements as the action repo).
- Access to the Compare-VI tooling (`Compare-VIHistory.ps1`,
  `Compare-RefsToTemp.ps1`, and supporting modules).

## One-off local run (labview-icon-editor example)

1. **Clone the target repo**

   ```powershell
   git clone https://github.com/LabVIEW-Community-CI-CD/labview-icon-editor.git
   ```

2. **Import the module**

   From the cloned `compare-vi-cli-action` repository run:

   ```powershell
   Import-Module (Join-Path $PWD 'tools/CompareVI.Tools/CompareVI.Tools.psd1') -Force
   ```

   The module exposes `Invoke-CompareVIHistory` and redirects all helper lookups
   back to this repository.

3. **Run the history helper**

   ```powershell
   Set-Location labview-icon-editor
   Invoke-CompareVIHistory `
     -TargetPath "resource/plugins/NIIconEditor/Miscellaneous/Settings Init.vi" `
     -MaxPairs 6 `
     -RenderReport `
     -FailOnDiff:$false `
     -InvokeScriptPath ..\compare-vi-cli-action\tools\Invoke-LVCompare.ps1
   ```

   - Outputs land in `tests/results/ref-compare/history/` inside the cloned
     repo (`history-report.md`, `history-report.html`, manifest JSON, etc.).
   - Works for any VI path with commit history; use `-StartRef` if you need to
     anchor to an older commit.
   - When LabVIEW is not available locally, point `-InvokeScriptPath` at a
     testing stub so the pipeline still emits manifests and reports.

### Reference fixtures

The repository ships a synthetic snapshot under
`fixtures/cross-repo/labview-icon-editor/settings-init/` (Markdown, HTML, and
JSON manifests). `tests/CompareVI.CrossRepo.Fixtures.Tests.ps1` validates that
the recorded metadata bucket counts (2 entries in the `metadata` bucket) stay
in sync with the documentation. Use the fixture as a template when capturing
new cross-repo runs.

## Observations / gaps

- With `CompareVI.Tools` we can reuse `Compare-VIHistory` and
  `Compare-RefsToTemp` without copying scripts into the target repository.
- We should publish a reusable workflow or module so that downstream projects
  can run Compare-VIHistory end-to-end without cloning this repository.

## Packaging decision (2025-10-31)

For issue #527 we will proceed with the **PowerShell module** approach:

- Create a module (working name `CompareVI.Tools`) that exports
  `Compare-VIHistory`, `Compare-RefsToTemp`, bucket metadata helpers, and the
  vendor resolver.
- Publish the module as part of the compare-vi-cli-action release process,
  making it installable via `Install-Module` / `Save-Module`.
- Provide a simple wrapper script so GitHub workflows can import the module and
  invoke `Compare-VIHistory` without copying files.
- Still generate a zip bundle from the release pipeline for consumers that
  prefer fixed artifacts (secondary path).

## Next steps (tracked by issue #527)

- **Packaging options**  
  - *PowerShell module*: publish `Compare-VIHistory`, `Compare-RefsToTemp`,
    bucket metadata, and vendor resolvers as a module (e.g.,
    `CompareVI.Tools`). External repos add a `Install-Module` step or pin the
    package via `Save-Module`.  
  - *Release bundle*: ship the helper scripts as a zip artifact on each
    release. Downstream workflows download/unpack into `tools/`.  
  - *Reusable workflow/composite action*: wrap the helper in a GitHub Action
    that accepts repo+VI inputs and runs the history capture on a trusted
    runner.

- **Automation gaps to close**
  - Publish one of the packaging options so consumers do not copy scripts
    manually.
  - Provide a sample workflow (e.g., `vi-history-cross-repo.yml`) that
    downloads the helper and runs it against a supplied repo/ref.
  - Clarify access requirements (SAML, LFS, large history impacts) in the docs.
  - Add validation that warns when the target VI has no history (e.g., history
    report shows only `_missing-base_` rows).
