# Self-hosted runner setup (Windows, LabVIEW 2025 Q3)

Prerequisites

- Windows Server or Windows 10/11 with administrator access
- LabVIEW 2025 Q3 installed and licensed for the service account running the GitHub runner

Steps

1) Install GitHub runner (self-hosted, Windows)
   - Follow the GitHub guide: <https://docs.github.com/en/actions/hosting-your-own-runners/adding-self-hosted-runners>
   - Run the runner as a service under a user with a valid LabVIEW license

2) Install LabVIEW 2025 Q3
   - Verify `LVCompare.exe` exists after installation
   - **Required canonical path**: `C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe`
   - This is the ONLY supported location; no other paths will work

3) Make the compare CLI discoverable
   - The action will automatically find the CLI at the canonical path
   - Optionally set environment variable for explicit configuration:
     - `LVCOMPARE_PATH=C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe`
     - Restart the runner service after changes
   - Or provide `lvComparePath` input in workflows
   - **Important**: All paths must resolve to the canonical location

4) Validate access
   - Run the repository’s “Smoke test Compare VI action” workflow (manual) and provide two `.vi` file paths
   - Confirm outputs `diff`, `exitCode`, `cliPath`, and `command`

Notes

- Ensure the runner service account has GUI-less access sufficient for CLI tools provided by LabVIEW
- Keep LabVIEW patched at the 2025 Q3 level used by your organization
- **Path policy**: Only the canonical path is supported to ensure consistency across runners
