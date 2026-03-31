# Fork Lane Configuration Management Plan

## Scope

- Product or service:
  Fork-lane local assurance control plane for issue `#2078`
- Managed baselines:
  `issue/2078-pester-layered-execution` on the fork, the checked-in fork-lane
  manifests, and the local assurance evidence set under
  `tests/results/_agent/fork-lanes/local-assurance`

## Configuration Items

| CI | Type | Owner | Baseline Rule |
| --- | --- | --- | --- |
| Fork-lane manifests | Configuration data | Engineering | Versioned on the issue branch and reconciled through `index.yaml` |
| Local assurance runner | Code | Engineering | Changed only through issue-scoped review |
| Assurance evidence | Artifact | Engineering | Regenerated for each meaningful fork-lane baseline |
| Fork-lane docs | Document | Engineering | Versioned with the issue branch baseline |

## Versioning

- Scheme: `v0.1.0` for the fork-lane assurance packet
- Tag trigger:
  A stable fork-lane baseline may be marked with a SemVer tag when the issue is
  ready to close or mount upstream.
- Release branch rule:
  Fork-lane control-plane changes stay on the issue branch until intentionally
  promoted.

## Change Control

| Change Type | Approval | Timing |
| --- | --- | --- |
| Standard | Local issue owner plus branch review | Before push |
| Urgent | Issue owner | Same day |
| Concession | Issue owner with issue comment | Before merge or closure |

## Status Accounting

- Record location:
  `tools/priority/fork-lanes/index.yaml`, `tools/priority/fork-lanes/issue-2078.yaml`, and the local assurance report
- Release record owner:
  Issue `#2078`
- Audit trail:
  Git history plus the assurance JSON and Markdown summaries

## Baseline And Release Evidence

- Baseline changes are recorded as explicit branch commits.
- Release procedure for the fork-lane packet is captured in
  `docs/release-procedure-fork-lane.md`.
- Release evidence retention requires the assurance report and summary to remain
  with the baseline commit.
