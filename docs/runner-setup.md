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
   - Typical paths:
     - `C:\Program Files\NI\LabVIEW 2025\LVCompare.exe`
     - `C:\Program Files\National Instruments\LabVIEW 2025\LVCompare.exe`

3) Make the compare CLI discoverable
   - Preferred: set a machine-level environment variable
     - `LVCOMPARE_PATH=C:\Program Files\NI\LabVIEW 2025\LVCompare.exe`
     - Restart the runner service after changes
   - Alternatives:
     - Add the containing folder to `PATH`
     - Provide `lvComparePath` input in the workflow

4) Validate access
   - Run the repository’s “Smoke test Compare VI action” workflow (manual) and provide two `.vi` file paths
   - Confirm outputs `diff`, `exitCode`, `cliPath`, and `command`

Notes

- Ensure the runner service account has GUI-less access sufficient for CLI tools provided by LabVIEW
- Keep LabVIEW patched at the 2025 Q3 level used by your organization
