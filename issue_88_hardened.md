## Summary
Track first╬ô├ç├ªclass developer╬ô├ç├ªexperience (DX) enhancements that a Codex agent can implement while I remain in the driver╬ô├ç├ûs seat. The agent may operate autonomously for routine tasks but must remain transparent and interruptible.

## Goals
- Reliable, low╬ô├ç├ªfriction PR comment dispatch with visible, self╬ô├ç├ªdescribing runs.
- Zero ╬ô├ç┬úsilent no╬ô├ç├ªops╬ô├ç┬Ñ: every attempted dispatch must acknowledge intent and link where to monitor.
- Clear provenance and outcome in run summaries/artifacts, no artifact╬ô├ç├ªdigging required for basics.
- Safe autonomy: the agent self╬ô├ç├ªdrives routine ops; I can stop at any point.

## Enhancements (Planned)
1) Comment DX
- Pre/post dispatch replies (done) ╬ô├Ñ├å refine with direct run URL once visible.
- Auto sample_id if omitted; echo back exact filters used.
- Busy╬ô├ç├ªrunner notice + suggested next action (e.g., single╬ô├ç├ªonly). 

2) Provenance & Observability
- Provenance in all orchestrated paths (done), extend to other workflows (validate, smoke, integration).
- Add ╬ô├ç┬úRun Links╬ô├ç┬Ñ block mapping job names ╬ô├Ñ├å direct log URLs.

3) Invoker Orchestration
- READY gating and boot.log (done) ╬ô├Ñ├å add aggregate step to summarize attempts across categories.
- Auto backoff policy: escalate retries/delay when recent runs show READY timeouts.

4) Outcome Surfacing
- Parse compare╬ô├ç├ªexec.json (done) ╬ô├Ñ├å also surface when absent and why (skipped/not produced).
- Add compact diff URL/paths (when available) to summary.

5) Concurrency & Policy
- Comment policy: single strategy preferred when runner busy; matrix only when idle.
- Auto╬ô├ç├ªcancel older in╬ô├ç├ªprogress orchestrated runs on same branch/sample group (opt╬ô├ç├ªin).

6) UX Polish
- ╬ô├ç┬úRe╬ô├ç├ªrun with same inputs╬ô├ç┬Ñ quick╬ô├ç├ªlink in the summary.
- ╬ô├ç┬úOpen most recent run╬ô├ç┬Ñ helper for PR via comment command.

## Guardrails (Autonomy)
- Agent must: (1) acknowledge intent in PR comment, (2) show inputs (strategy, sample_id, ref), (3) provide a monitor link, (4) print provenance in run, (5) never claim a trigger without proof (run link or explicit notice).
- No destructive actions (cancels, cleanup) without explicit policy flags.

## Acceptance Criteria

1) Comment Dispatch (PR)
- Ack within 10s: PR reply includes ref, strategy, include_integration, sample_id, origin (author, PR, comment link).
- Monitor link: follow-up PR reply contains a direct workflow URL filtered by branch; if not visible yet, include the generic workflow page and say “initializing”.
- Zero silent no‑ops: 100% of /run orchestrated comments either dispatch (and reply with links) or reply with a concrete reason (unauthorized, disabled, malformed). No ambiguous outcomes.
- API integrity: agent never claims success on non-2xx dispatch; replies include the HTTP error code on failure.
- Idempotency: duplicate comments within 60s (same strategy and sample_id) do not produce >1 run.

2) Provenance & Observability
- Summary must include a “Run Provenance” block with: runId, runAttempt, workflow, ref, head/base (when applicable), origin_kind, origin_pr, origin_comment_id/url, origin_author, sample_id, include_integration, strategy.
- Artifact `orchestrated-provenance` exists with `tests/results/provenance.json` matching the summary values.
- Schema-lite validation passes for provenance.json.

3) Invoker Stability & Gating
- Single strategy: achieve 2 consecutive green runs where boot.log shows READY observed ≤ 30s and ≤ 2 attempts. Heavy steps executed (no READY skips).
- Matrix strategy: 1 green run where all categories pass invoker READY (per-category boot logs uploaded).
- Not READY path: heavy steps are skipped; boot.log uploaded; summary contains “invoker not READY — timeout (attempts=X, delay=Y, to=Z)”.
- Process snapshots: at least one pre/post snapshot section present per job with pwsh/LVCompare/LabVIEW PIDs.

4) Warmup & Race Avoidance
- Warmup runs only after invoker start and in preflight mode (no VI args). LVCompare left running.
- No observed case where warmup (or any step) occurs before invoker READY attempt window starts; snapshots reflect ordering (invoker start → warmup).

5) Compare Outcome Surfacing
- When drift runs, summary includes a “Compare Outcome” block with: file, diff, exitCode, durationMs, cliPath, command.
- Artifact `compare-outcome-drift` exists (compare-outcome.json). If `compare-exec.json` is missing, summary states “no compare-exec.json” and a reason code: no_exec_json|no_cli|missing_vi|invoker_not_ready|skipped.
- Schema-lite validation (if added) passes for compare-outcome.json.

6) Busy‑Runner Experience
- If the runner is busy, the dispatcher posts a “queued/busy” PR reply within 10s with the monitor link. No silent failures.
- Single strategy reliably completes under typical load; matrix may be delayed by policy — delay/queue reason must be explicit in PR reply.

7) Summary Structure & UX
- Every orchestrated run’s summary includes, in order: Run Provenance, Invoker/Process Snapshot (at least one), Compare Outcome (when drift runs), Re-run hint (strategy, sample_id pre-filled).
- “Re-run with same inputs” quick-link or hint present in PR reply or run summary.

8) Resilience & Backoff
- Dispatch path retries once on transient HTTP failures (5xx/network) with a backoff; failures report final status.
- Invoker backoff policy escalates (e.g., retries/delay) after two consecutive READY timeouts on the same branch (configurable), and the summary states the escalated settings used.## Non╬ô├ç├ªGoals
- Changing business logic of compare/report beyond surfacing outcomes.

## Links
- Orchestrated Unification PR: #85
- Comment Dispatcher Update: #86
- Bug (invoker race/outcome): #87

