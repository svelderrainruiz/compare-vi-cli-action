# Deterministic VI history slice selection contract

**Issue:** `#1011`  
**Labels:** enhancement, ci

## Summary

Replace symbolic `HistoryBranchRef`-first selection with a deterministic
`vi-history-slice@v1` contract that resolves an immutable history slice before
any VI history or NI Linux container execution begins.

## Motivation

- Symbolic refs such as `HEAD` are checkout-shape dependent and can resolve to
  different commit graphs on hosted PR runs, local worktrees, and cross-repo
  mirrors.
- Commit count is useful as a bound, but not as identity. The executor needs a
  stable description of exactly which commit pairs to process.
- Hosted Ubuntu runners should be able to process multiple branch bundles
  concurrently without inferring branch meaning from runner-local state.

## Proposed contract

### 1. Selector

Human- or workflow-facing input that describes intent:

- `targetPath`
- `headSha`
- `baselineSha` or `baselineMode`
- `historyMode` (`first-parent`, `ancestry-path`, `explicit-list`)
- `maxCommitCount`
- `maxPairs`
- `pathFilter`
- `repoIdentity`
- `selectionPolicyVersion`

### 2. Resolved slice manifest

Machine-facing manifest generated before any compare work:

- `schema`
- `headSha`
- `baselineSha`
- `mergeBaseSha`
- ordered `commits[]`
- ordered `pairs[]`
- `commitCount`
- `historyMode`
- `sliceDigest`

### 3. Execution bundle

Container and report helpers consume only the resolved manifest:

- no symbolic `HEAD`
- no branch-name interpretation inside the container
- no runner-specific ref heuristics

## Compatibility strategy

- Keep `HistoryBranchRef` as a compatibility shim temporarily.
- Resolve legacy inputs into `vi-history-slice@v1` before bootstrap execution.
- Record both requested legacy inputs and effective resolved slice metadata in
  review artifacts until the symbolic path is retired.

## Non-destructive scaffolding goals

- Add the selector/manifest schema surface without changing default report
  behavior.
- Add contract tests for slice resolution and artifact identity.
- Keep existing PR 1009 review/report paths working while the new surface is
  introduced behind additive parameters.

## Acceptance criteria

- [ ] A reusable resolver produces the same slice manifest across Windows,
      Ubuntu, local worktrees, and hosted PR checkouts.
- [ ] Review-suite and pre-push helpers can accept a pre-resolved slice manifest
      instead of symbolic refs.
- [ ] The NI Linux container path runs from resolved slice input only.
- [ ] Artifacts expose `sliceDigest` so concurrent runs can be correlated
      without branch-name ambiguity.
- [ ] Legacy `HistoryBranchRef` entry points remain functional during the
      migration window.

## Risks

- Contract sprawl if both symbolic and deterministic inputs remain first-class
  for too long.
- Cross-repo fetch depth or missing SHAs can make resolution fail unless the
  caller fetches the required objects first.
- Consumers may treat `maxCommitCount` as identity unless the manifest digest is
  clearly documented as the canonical execution key.
