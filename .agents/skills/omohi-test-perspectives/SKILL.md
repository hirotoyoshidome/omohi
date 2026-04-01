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

## Minimum Scenario Checklist
- Happy path
- Expected domain or use-case failure
- Boundary or contract edge case
- Persistence or lock-related invariant when applicable
- Exit-code regression when CLI-visible behavior changes

## Completion Criteria
- Add or update only the tests needed to protect the changed contract.
- State uncovered risks explicitly if some scenarios are not tested.
