# PR: Scaffold CompareVi.Shared (.NET 8) + Build Workflow

Summary
- Adds a reusable .NET 8 class library `CompareVi.Shared` with:
  - `ArgTokenizer`: quote-aware tokenization and `-flag=value` normalization
  - `PathUtils`: Windows path normalization and safe quoting
  - `ProcSnapshot`: capture/diff process snapshots and close newly spawned LabVIEW PIDs
- Adds CI workflow `.github/workflows/dotnet-shared.yml` to build/pack on changes under `src/**` and upload `.nupkg`.
- Adds local builder `tools/Build-Shared.ps1` and short docs in `docs/SHARED_LIB.md`.

Why
- Consolidate cross-repo helpers (arg parsing, path normalization, process cleanup) behind a typed API.
- Prepare for gradual adoption in this repo and future repos without duplicating logic.

Scope / Risk
- No runtime behavior changes to existing PowerShell scripts in this PR.
- Library is built and published as an artifact only; not yet consumed by scripts.

Validation
- Local and CI build: `dotnet restore/build/pack` succeeds on .NET 8.
- Artifacts: `.nupkg` uploaded by workflow.

Follow-ups (separate PR)
- Adopt ArgTokenizer/PathUtils in PowerShell with parity tests.
- Optional: publish to GitHub Packages and add a PowerShell binary module wrapper.

Checklist
- [x] Build green on .NET workflow
- [x] Docs added (`docs/SHARED_LIB.md`)
- [x] No changes to existing test flows
- [x] Ready for review

