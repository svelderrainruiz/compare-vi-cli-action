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

2. **Copy the helper script**

   `Compare-VIHistory.ps1` expects `tools/Compare-RefsToTemp.ps1` to be present
   in the target repo. For now, copy it from this repo:

   ```powershell
   New-Item -ItemType Directory labview-icon-editor/tools -Force | Out-Null
   Copy-Item ..\compare-vi-cli-action\tools\Compare-RefsToTemp.ps1 `
     labview-icon-editor\tools\Compare-RefsToTemp.ps1 `
     -Force
   ```

3. **Run the history helper**

   ```powershell
   pwsh -File ..\compare-vi-cli-action\tools\Compare-VIHistory.ps1 `
     -TargetPath "resource/plugins/NIIconEditor/Miscellaneous/Settings Init.vi" `
     -MaxPairs 6 `
     -RenderReport `
     -FailOnDiff:$false
   ```

   - Outputs land in `tests/results/ref-compare/history/` inside the cloned
 repo (`history-report.md`, `history-report.html`, manifest JSON, etc.).
 - Works for any VI path with commit history; use `-StartRef` if you need to
   anchor to an older commit.

### Using the module wrapper

Once `CompareVI.Tools` is published you can replace steps 2–3 with:

```powershell
Import-Module CompareVI.Tools
Set-Location labview-icon-editor
Invoke-CompareVIHistory `
  -TargetPath "resource/plugins/NIIconEditor/Miscellaneous/Settings Init.vi" `
  -MaxPairs 6 `
  -RenderReport
```

The module sets up the helper path automatically; downstream repos simply need
the module on the PowerShell module path.

## Observations / gaps

- The only blocker for external repos is shipping `Compare-RefsToTemp.ps1`.
  Packaging that helper (PowerShell module, shared zip, or workflow download)
  would eliminate manual copying.
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
