<!-- markdownlint-disable-next-line MD041 -->
# Release v0.5.1

Highlights

- Fixture manifest now exposes a `pair` block (schema `fixture-pair/v1`) with canonical SHA digests and outcome hints.
- Integration runbook falls back to repository fixtures (`VI1.vi` / `VI2.vi`) when `LV_BASE_VI` / `LV_HEAD_VI` are unset,
  ensuring ViInputs succeeds on default environments.
- Release simulator (`node tools/npm/run-script.mjs priority:release`) now writes `release-summary.json` reliably so
  release handoff artifacts stay in sync.

Upgrade Notes

- If you consume `fixtures.manifest.json`, adopt the new `pair` metadata and update validators to read the exact digest.
- No changes to action inputs/outputs; dispatcher JSON artifacts remain additive.

Validation Checklist

- [ ] `./Invoke-PesterTests.ps1` (hosted Windows slice) covering Run-AutonomousIntegrationLoop passes.
- [ ] `./Invoke-PesterTests.ps1 -IntegrationMode include` green on self-hosted runner.
- [ ] Fixture Drift jobs on Windows/Ubuntu succeed (`tests/results/teststand-session/session-index.json` is current).
- [ ] Validate workflow (actionlint + docs links) green — see run [18635539468](https://github.com/svelderrainruiz/compare-vi-cli-action/actions/runs/18635539468).
- [ ] LabVIEW CLI guard (`tools/TestStand-CompareHarness.ps1`) exits cleanly and produces the HTML report.

Post-Release

- Tag v0.5.1 on main.
- Update `POST_RELEASE_FOLLOWUPS.md` to reflect completed roadmap items for 0.5.1.
