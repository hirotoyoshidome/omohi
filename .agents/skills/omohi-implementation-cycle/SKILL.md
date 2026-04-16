---
name: omohi-implementation-cycle
description: Use this for any implementation task (feature, fix, refactor). Enforces the cycle - implement → test → self-review. Do not declare a task complete until the self-review pass is finished.
---

# omohi Implementation Cycle

## Required Reading
Before starting, read the following.

1. `AGENTS.md`
2. `docs/Zig-coding-rules.md`
3. `docs/codex-common-rules.md`
4. Only the task-relevant specs under `docs/` or `codex-md/`

## Phase 1: Implement
1. Follow `omohi-zig-implementation` for design decisions and coding rules.
2. Follow `omohi-dependency-guard` for import and placement validation.

## Phase 2: Test
1. Add or update tests following `omohi-test-perspectives`.
2. Run `make test` and confirm all tests pass.
3. Run `make fmt-check` and fix any formatting issues.
4. If the change touches CLI behavior, also run `make test-contract` and `make test-completion`.

## Phase 3: Self-Review
After implementation and tests pass, perform a self-review using the following checklist. Do not skip this phase.

### Review Checklist
Apply every applicable item. For each, state "OK" or describe the issue found.

1. **Whole-system impact**: Does this change push complexity into a neighbor?
2. **Type proliferation**: Does this change duplicate an existing type or enum?
3. **Function granularity**: Are any new or modified functions over 80 lines or mixing validation, I/O, and business logic?
4. **File granularity**: Does any modified file exceed 500 lines with mixed responsibilities?
5. **Comptime enforcement**: Are there runtime checks on comptime-known values that could be compile-time assertions?
6. **Test coverage**: Does every public function in the changed files have at least a success-path test? Are error paths covered?
7. **OS dependency**: Does the change use `std.posix`, `builtin.os`, or spawn external processes? If so, apply `omohi-platform-guard`.
8. **Access scope**: Are all added `pub` declarations necessary? Is anything exposed that should be internal?
9. **Documentation freshness**: If CLI, persistence layout, domain constraints, or test policy changed, are the relevant sections of `AGENTS.md` and generated docs updated?
10. **Boundary alignment**: Is the dependency direction `app/cli -> ops -> store/api.zig` preserved?
11. **Contract preservation**: Are CLI exit codes, message formats, and persistence formats unchanged (or intentionally updated with test coverage)?

### Completion Criteria
- All checklist items are addressed.
- All tests pass (`make test` at minimum; `make check` for broad changes).
- Formatting is clean (`make fmt-check`).
- Issues found during self-review are fixed before declaring the task complete.
- If an issue is deferred, state the reason and create a tracking note.
