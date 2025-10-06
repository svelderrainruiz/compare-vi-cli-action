# Summary
This issue tracks developer‑experience (DX) improvements that an agent can implement while I remain in control. The agent may operate autonomously for routine tasks, but must remain transparent, interruptible, and self‑describing.

## Goals
- Reliable PR comment dispatch with immediate, visible feedback.
- No silent no‑ops: every attempt acknowledges intent and shows where to monitor.
- Clear provenance and outcomes in job summaries and artifacts.
- Safe autonomy: routine steps run without prompts, but I can stop at any time.

## Enhancements (Agent Tasks)

- Comment DX
  - Pre/post dispatch PR replies with inputs and monitor link.
  - Auto sample_id when omitted; echo exact filters used.
  - Busy‑runner notice with suggested next action (e.g., single only).
- Provenance & Observability
  - Run provenance in summary and provenance.json artifact for all orchestrated paths.
  - Add a simple "Run Links" block mapping jobs to logs.
- Invoker Orchestration
  - READY gating with boot.log and process snapshots.
  - Auto backoff policy when READY timeouts repeat.
- Outcome Surfacing
  - Parse compare‑exec.json and print diff/exitCode/duration/command.
  - State why exec JSON is missing (skipped/not produced).
- Concurrency & Policy
  - Prefer single strategy when runner is busy; allow matrix when idle.
  - Optional auto‑cancel older in‑progress runs for same branch/group.
- UX Polish
  - "Re‑run with same inputs" quick hint in PR reply or summary.
  - "Open most recent run" helper command.

## Guardrails (Autonomy)

- Always acknowledge intent in PR comment with inputs and a monitor link.
- Print provenance in the run and upload provenance.json.
- Never claim a trigger without a link or an explicit reason.
- No destructive actions (cancels/cleanup) without explicit policy flags.

## Acceptance Criteria (Hardened)

1) Comment Dispatch (PR)
- Ack within 10s: PR reply includes ref, strategy, include_integration, sample_id, origin (author, PR, comment link).
- Monitor link: follow‑up PR reply contains a workflow URL filtered by branch; if not visible yet, show the generic workflow page and say "initializing".
- Zero silent no‑ops: 100% of /run orchestrated comments either dispatch (with links) or reply with a concrete reason (unauthorized, disabled, malformed).
- API integrity: never claim success on non‑2xx dispatch; include HTTP code on failure.
- Idempotency: duplicate comments within 60s (same strategy and sample_id) do not produce more than one run.

2) Provenance & Observability
- Summary contains a "Run Provenance" block with: runId, runAttempt, workflow, ref, head/base (when applicable), origin_kind, origin_pr, origin_comment_id/url, origin_author, sample_id, include_integration, strategy.
- Artifact orchestrated‑provenance contains tests/results/provenance.json matching the summary.
- Schema‑lite validation passes for provenance.json.

3) Invoker Stability & Gating
- Single strategy: two consecutive green runs where boot.log shows READY observed within 30s and in two attempts or fewer; heavy steps executed (no READY skips).
- Matrix strategy: one green run where all categories pass invoker READY (per‑category boot logs uploaded).
- Not READY path: heavy steps are skipped; boot.log is uploaded; the job summary states "invoker not READY — timeout (attempts=X, delay=Y, to=Z)".
- Process snapshots: at least one pre/post snapshot section present per job with pwsh/LVCompare/LabVIEW PIDs.

4) Warmup & Race Avoidance
- Warmup runs only after invoker start and in preflight mode (no VI args). LVCompare remains running.
- No observed case where warmup occurs before invoker READY attempt window begins; snapshots reflect ordering (invoker start, then warmup).

5) Compare Outcome Surfacing
- When drift runs, summary includes a "Compare Outcome" block with: file, diff, exitCode, durationMs, cliPath, command.
- Artifact compare‑outcome‑drift exists (compare‑outcome.json). If compare‑exec.json is missing, summary states "no compare‑exec.json" and a reason code: no_exec_json | no_cli | missing_vi | invoker_not_ready | skipped.
- (Optional) schema‑lite validation passes for compare‑outcome.json.

6) Busy‑Runner Experience
- When the runner is busy, the dispatcher replies "queued/busy" within 10s and provides a monitor link. No silent failures.
- Single strategy reliably completes under typical load; matrix may be delayed by policy, and delay reason is explicit in the PR reply.

7) Summary Structure & UX
- Every orchestrated run summary includes, in order: Run Provenance, Invoker/Process Snapshot (at least one), Compare Outcome (when drift runs), and a "Re‑run with same inputs" hint.

8) Resilience & Backoff
- Dispatch retries once on transient HTTP failures (5xx/network) with backoff; failures report final status.
- Invoker backoff escalates retries/delay after two consecutive READY timeouts on the same branch; the summary states the escalated settings used.

## Non‑Goals
- Changing compare/report business logic beyond surfacing outcomes and provenance.

## Links
- Orchestrated Unification PR: #85
- Comment Dispatcher Update: #86
- Invoker Race / Outcome Bug: #87
