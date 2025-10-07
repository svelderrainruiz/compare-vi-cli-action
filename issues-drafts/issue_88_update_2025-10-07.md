Title: Deterministic Compare Sequence + HTML Hardening — Local First (Update)

Summary

- Implemented a local, deterministic 4‑wire kernel as a sequence runner (tools/Run-CompareSequence.ps1) with a filesystem lock to prevent overlap: Compare → Verify (read‑only) → Render (read‑only) → Telemetry.
- Hardened the HTML report (scripts/Render-CompareReport.ps1):
  - Added Render Meta (Start/End UTC, Render Time ms, Pre/Post LVCompare/LabVIEW PIDs, New PIDs highlight).
  - Kept Summary fields safe: CLI Path, Base, Head show Copy buttons (no accidental launches).
  - Added badges, improved section cards, Agent Trace with Copy‑only commands, Verification signature (+ *.signature.txt).
- Validated locally: LVCompare.exe starts after HTML renders (not during). Render Meta + timestamps confirm sequencing.

Why this matters

- Determinism: one CompareVI invocation per sequence; all further passes are read‑only. No hidden or concurrent work.
- Evidence‑first DX: report bundles Content vs CLI, live processes, and render timing; Agent Trace shows exactly what ran.
- Works the same locally and on runner (invoker can slot in for the lock).

Next Actions (proposed)

1) HTML DX
   - Artifact Map: add Copy buttons next to file paths (keep file:/// for JSON/HTML; no links for VIs).
   - Optional post‑render sniff (RENDER_POST_SNIFF_MS) to append immediate births to Render Meta + tiny JSON.

2) Sequence kernel polish
   - Extend sequence runner with refs mode (path + refA/refB → Base.vi/Head.vi) and emit compare‑bundle.json (index of outputs).

3) CI integration
   - Composite action (compare-sequence) for self‑hosted/hosted; same passes and gates; upload HTML + signature + bundle.json.

Acceptance Criteria

- Local and runner sequences produce identical artifacts (except timestamps/signatures).
- HTML shows Render Meta with New LVCompare/New LabVIEW = empty unless user opens something.
- Verify is read‑only; no second LVCompare; Anomalies flags mismatches.

Repro (local)

- pwsh -File tools/Run-CompareSequence.ps1 -Base .\VI1.vi -Head .\VI2.vi -SeqId local-2 -Verify -Render -Telemetry
- Open results\local-2\compare-report.html

Artifacts of interest (current session)

- Fixtures HTML: results\local\compare-report-verify.html
- VI1 refs HTML: results\local\vi1-refs-report.html
- Signature: results\local\compare-report-verify.signature.txt

Notes/Risks

- Keep cleanup opt‑in (CLEAN_LVCOMPARE=1) to preserve evidence.
- Avoid Summary links to VI files; Copy‑only is intentional.
