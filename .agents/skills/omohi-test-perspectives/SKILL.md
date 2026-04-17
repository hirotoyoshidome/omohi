---
name: omohi-test-perspectives
description: Use this when creating or extending tests for omohi. Focus on contract coverage, destructive operations, persistence consistency, boundary behavior, and regression resistance.
---

# omohi Test Perspectives

## Required Reading
Before writing tests, read the following.

1. `AGENTS.md`
2. `docs/Zig-coding-rules.md`
3. `docs/codex-common-rules.md`
4. Only the task-relevant specs under `docs/` or `codex-md/`

## Test Priorities
Prefer coverage in the following order.

1. `store` behavior and persistence invariants
2. Destructive operations and lock behavior
3. ID generation and consistency rules
4. `ops` behavior and use-case error mapping
5. CLI parsing, exit codes, and message-contract regressions

## Test Design Viewpoints
- Test observable behavior and persisted results, not only intermediate implementation details.
- Cover success, failure, and recovery-oriented scenarios.
- Add regression tests for every bug fix and boundary-sensitive refactor.
- Prefer tests that validate durability invariants such as atomic write order, logical deletion behavior, and `HEAD` update ordering where relevant.
- Verify ownership and cleanup responsibilities when allocation or staged objects are involved.
- Mark test-only helper functions with `// TEST-ONLY: <reason>`.
- Put shared test-only helpers in `src/testing/` instead of exposing them through production Facades.
- For omohi CI placement:
  - Keep `main-smoke` focused on the must-not-break major-command path after merge to `main`.
  - Put broad CLI pattern coverage in the scheduled `e2e-matrix` job, including option combinations, aliases, parser boundaries, output modes, no-op behavior, and regression scenarios.
  - Do not put functional E2E coverage into `perf-baseline`.
  - Allow overlap between smoke and matrix tests when that makes the major-command path simpler to maintain.

## Minimum Scenario Checklist
- Happy path
- Expected domain or use-case failure
- Boundary or contract edge case
- Persistence or lock-related invariant when applicable
- Exit-code regression when CLI-visible behavior changes

## Coverage Gap Review
When reviewing changes, verify the following for the changed code:
- Every public function in the changed file has at least one test exercising its success path.
- Every error return in the changed function has at least one test triggering that error path.
- If the change introduces a new skip/fallback path in an outcome type, there is a test that exercises that path.
- If the change touches `store` layer persistence, there is a test that verifies the on-disk state (not just in-memory return values).
- If the change touches a constrained type, there is a test for both valid and invalid inputs at the boundary.
- Pure pass-through functions in `ops` that delegate to `store/api` without transformation do not require independent unit tests, provided the underlying `store/api` function is tested. If the `ops` function adds any logic (validation, error mapping, or aggregation), it requires its own tests.
- State which public functions lack tests and whether that gap is acceptable (e.g., trivial delegation) or needs coverage.

## Completion Criteria
- Add or update only the tests needed to protect the changed contract.
- When a change affects major-command survivability, check whether `main-smoke` should move with it.
- When a change affects CLI patterns or output contracts, update the matrix E2E coverage in the same change.
- State uncovered risks explicitly if some scenarios are not tested.
