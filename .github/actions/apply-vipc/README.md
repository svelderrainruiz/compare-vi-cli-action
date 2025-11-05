# Apply VIPC Dependencies 📦

Ensure a runner has all required LabVIEW packages installed before building or testing. This composite action calls **`ApplyVIPC.ps1`** to apply a `.vipc` container through the **VIPM CLI** (`vipm`). The action automatically detects the `runner_dependencies.vipc` file located in this directory.

---

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Inputs](#inputs)
3. [Quick-start](#quick-start)
4. [How it works](#how-it-works)
5. [Troubleshooting](#troubleshooting)
6. [License](#license)

---

## Prerequisites
| Requirement | Notes |
|-------------|-------|
| **Windows runner** | LabVIEW and the VIPM CLI are Windows only. |
| **LabVIEW** `>= 2021` | Must match both `minimum_supported_lv_version` and `vip_lv_version`. |
| **VIPM CLI (`vipm`)** | Install VIPM with CLI support and ensure the `vipm` executable is on `PATH`, or set `VIPM_CLI_PATH`. |
| **PowerShell 7** | Composite steps use PowerShell Core (`pwsh`). |

---

## Inputs
| Name | Required | Example | Description |
|------|----------|---------|-------------|
| `minimum_supported_lv_version` | **Yes** | `2021` | LabVIEW *major* version that the repo supports. |
| `vip_lv_version` | **Yes** | `2021` | LabVIEW version used to apply the `.vipc` file. Usually the same as `minimum_supported_lv_version`. |
| `supported_bitness` | **Yes** | `32` or `64` | LabVIEW bitness to target. |
| `relative_path` | **Yes** | `${{ github.workspace }}` | Root path of the repository on disk. |
| `toolchain` | No | `vipm-cli` | Provider to use (fixed to `vipm-cli`). |

---

## Quick-start
```yaml
# .github/workflows/ci-composite.yml (excerpt)
steps:
  - uses: actions/checkout@v4
  - name: Install LabVIEW dependencies
    uses: ./.github/actions/apply-vipc
    with:
      minimum_supported_lv_version: 2021
      vip_lv_version: 2021
      supported_bitness: 64
      relative_path: ${{ github.workspace }}
```

The CI pipeline applies these dependencies across multiple LabVIEW versions—2021 (32-bit and 64-bit) and 2025 (64-bit)—as shown in
[`.github/workflows/ci-composite.yml`](../../workflows/ci-composite.yml).

---

## How it works
1. **Checkout** – pulls the repository to ensure scripts and the `.vipc` file are present.
2. **PowerShell wrapper** – executes `ApplyVIPC.ps1` with the provided inputs.
3. **Provider selection** - `ApplyVIPC.ps1` invokes the **VIPM CLI** to apply the `.vipc` container. The `toolchain` input is exposed for compatibility but only `vipm-cli` is supported.
4. **Failure propagation** – any error in path resolution, the VIPM CLI call, or the script causes the step (and job) to fail.

---

## Troubleshooting
| Symptom | Hint |
|---------|------|
| *VIPM CLI executable not found* | Install VIPM (with CLI support) and ensure `vipm` is on `PATH`, or set `VIPM_CLI_PATH` to the executable. |
| *`.vipc` file not found* | Ensure `runner_dependencies.vipc` exists in this action directory. |
| *LabVIEW version mismatch* | Make sure the installed LabVIEW version matches both version inputs. |

---

## License
This directory inherits the root repository’s license (MIT, unless otherwise noted).


