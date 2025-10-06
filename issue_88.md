## Summary
Track first-class developer-experience (DX) enhancements that a Codex agent can implement while I remain in the driver's seat. The agent may operate autonomously for routine tasks but must remain transparent and interruptible.

## Goals

- Reliable, low-friction PR comment dispatch with visible, self-describing runs.
- Zero "silent no-ops": every attempted dispatch must acknowledge intent and link where to monitor.
- Clear provenance and outcome in run summaries/artifacts, no artifact-digging required for basics.
- Safe autonomy: the agent self-drives routine ops; I can stop at any point.

## Enhancements (Planned)

### 1) Comment DX

- Pre/post dispatch replies (done) -> refine with direct run URL once visible.
- Auto sample_id if omitted; echo back exact filters used.
- Busy-runner notice + suggested next action (e.g., single-only).

### 2) Provenance & Observability

- Provenance in all orchestrated paths (done), extend to other workflows (validate, smoke, integration).
- Add "Run Links" block mapping job names -> direct log URLs.

### 3) Invoker Orchestration

- READY gating and boot.log (done) -> add aggregate step to summarize attempts across categories.
- Auto backoff policy: escalate retries/delay when recent runs show READY timeouts.

### 4) Outcome Surfacing

- Parse compare-exec.json (done) -> also surface when absent and why (skipped/not produced).
- Add compact diff URL/paths (when available) to summary.

### 5) Concurrency & Policy

- Comment policy: single strategy preferred when runner busy; matrix only when idle.
- Auto-cancel older in-progress orchestrated runs on same branch/sample group (opt-in).

### 6) UX Polish

- "Re-run with same inputs" quick-link in the summary.
- "Open most recent run" helper for PR via comment command.

## Guardrails (Autonomy)

- Agent must: (1) acknowledge intent in PR comment, (2) show inputs (strategy, sample_id, ref), (3) provide a monitor link, (4) print provenance in run, (5) never claim a trigger without proof (run link or explicit notice).
- No destructive actions (cancels, cleanup) without explicit policy flags.

## Acceptance Criteria

### 1) Comment Dispatch (PR)

- The dispatcher posts an acknowledgement within 10s including: ref, strategy, include_integration, sample_id, origin (author, PR, comment link).
- A follow-up comment includes a monitor link (workflow runs filtered by branch).
- 100% of /run orchestrated comments either (a) dispatch and reply with links, or (b) reply with a clear reason (e.g., unauthorized, disabled) — zero silent no-ops.

### 2) Provenance & Observability

- Orchestrated job summary contains a "Run Provenance" block with: runId, runAttempt, workflow, ref, head/base (when applicable), origin_kind, origin_pr, origin_comment_id/url, origin_author, sample_id, include_integration, strategy.
- Artifact orchestrated-provenance exists and contains tests/results/provenance.json matching the summary values.

### 3) Invoker Stability

- For single strategy: 2 consecutive green runs on the self-hosted runner where boot.log shows READY within 30s and <= 2 attempts; heavy steps executed (no skips due to READY).
- For matrix strategy: 1 green run with all categories passing invoker READY; per-category boot logs uploaded.
- When READY is not reached, heavy steps are skipped, boot.log is uploaded, and the job summary explains the skip ("invoker not READY - timeout").

### 4) Warmup & Race Avoidance

- Warmup runs after invoker start in preflight mode (no VI args) and leaves LVCompare running.
- No observed case where warmup (or any step) causes invoker to start late; process snapshots show expected ordering (invoker start -> warmup).

### 5) Compare Outcome Surfacing

- When drift runs, the job summary contains a "Compare Outcome" block with: file, diff, exitCode, durationMs, cliPath, command.
- Artifact compare-outcome-drift exists (compare-outcome.json). If compare-exec.json is missing, the summary states "no compare-exec.json" and why (skipped/not produced).

### 6) Busy-Runner Experience

- When the runner is busy, the dispatcher still posts a reply indicating queueing/busy and provides a monitor link. No silent failures.
- Single strategy runs reliably complete under typical load; matrix can be delayed per policy.

### 7) UX Quality Bar

- Every orchestrated run's summary is scannable and contains three sections at minimum: Run Provenance, Invoker/Process Snapshot (at least one), and Compare Outcome (when drift runs).
- A "Re-run with same inputs" quick hint is present in summaries or PR replies.

## Non-Goals

- Changing business logic of compare/report beyond surfacing outcomes.

## Links

- Orchestrated Unification PR: #85
- Comment Dispatcher Update: #86
- Bug (invoker race/outcome): #87
