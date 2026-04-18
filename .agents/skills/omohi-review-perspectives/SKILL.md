---
name: omohi-review-perspectives
description: Use this when reviewing omohi changes. Focus on boundary correctness, durability, contracts, ownership, destructive behavior, comment quality, and test adequacy rather than local style alone.
---

# omohi Review Perspectives

## Required Reading
Before reviewing, read the following.

1. `AGENTS.md`
2. `docs/Zig-coding-rules.md`
3. `docs/codex-common-rules.md`
4. Only the task-relevant specs under `docs/` or `codex-md/`

## Review Priorities
Review in the following order.

1. Philosophy alignment: local-first, non-destructive, process logging
2. Boundary alignment: `app/cli -> ops`, `ops` must not import other `ops`, and `ops -> store/api.zig`
3. External contract preservation: CLI behavior, exit codes, persistence format
4. Durability and destructive-operation safety
5. Ownership, lifetime, allocator, and error handling
6. Comment and documentation adequacy
7. Test sufficiency

## Review Viewpoints
- Check whether the change improves the whole system, not only the touched function or file.
- Check whether abstractions reduce long-term cost instead of only hiding local complexity.
- Check whether destructive paths preserve lock, atomic write, and recovery expectations.
- Check whether public boundaries stay minimal and internal details do not leak.
- Check whether comments explain purpose, ownership, lifetime, exceptional choices, and non-obvious tradeoffs.
- Check whether test-only helpers are marked with `// TEST-ONLY:`.
- Check whether tests cover behavior regressions, not only implementation shape.

### Whole-System Impact
- When a change simplifies one module, check whether it pushes complexity into a neighbor (caller, callee, or sibling module).
- When adding a new function or type, check whether an existing one in the same layer already serves the purpose. Duplication across layers is acceptable only when the layers assign different semantics.
- When fixing a bug, check whether the root cause is in the current module or in a dependency. A local workaround that masks a deeper issue is not acceptable unless the dependency is frozen or external.
- When refactoring, measure the change against three axes: boundary clarity, testability, and long-term maintenance cost. A refactor that improves only one axis while degrading another requires explicit justification.

### Type Proliferation
- Before creating a new struct, search for existing types with overlapping fields in the same layer.
  - In `store`: check `constrained_types.zig` and `api_types.zig` first.
  - In `app/cli`: check `parser/types.zig` and `runtime/types.zig` first.
- Constrained ID types (`TrackedFileId`, `StagedFileId`, `CommitId`, `SnapshotId`, `ContentHash`) share a common validation pattern. When adding a new ID type, reuse the existing `parseHexFixed` / `validateAbsolutePathWithoutParent` helpers in `constrained_types.zig` rather than writing new validation.
- Do not duplicate an enum across layers. If both `store` and `app/cli` need the same enum (e.g., `FindEmptyFilter`), define it once in `store` and re-export through the Facade.
- Collection type aliases (`StringList`, `TagList`, etc.) must be defined in one place and imported, not redefined with the same underlying type in multiple files.
- Outcome types (`AddBatchOutcome`, `RmBatchOutcome`, `TrackOutcome`) follow a counter-based pattern. When adding a new outcome type, follow the same structure: a list of successful items + named skip counters + `init` method.

### Function Granularity
- A function should be describable in one sentence without "and." If the description requires "and," consider splitting.
- A function exceeding 80 lines is a review signal. Check whether it mixes validation, I/O, and business logic. If it does, split along those boundaries.
- A function that is a pure pass-through (delegates to a single call with no transformation) is acceptable only at a layer boundary (e.g., `ops` wrapping `store/api`). Within the same layer, inline the call instead.
- When a function contains a large `switch` or branching block, check whether the branches can be driven by data (comptime table or tagged union) rather than code.
- Test-only helper functions are exempt from the 80-line guideline but must still have a single purpose. Mark them with `// TEST-ONLY: <reason>`.

### File Granularity
- Each file should represent one cohesive responsibility. If the file's name cannot describe all of its contents, it has mixed responsibilities.
- A file exceeding 500 lines is a review signal. Check whether it can be split into modules with narrower responsibilities while preserving the public API through a single entry-point file.
- A Facade file (e.g., `api.zig`) may be large because it re-exports many modules. In that case, check whether the implementation functions can move into sub-modules, keeping the Facade as a thin aggregator of explicit re-exports.
- When a file contains both production code and large test fixtures (over 100 lines of test setup), extract the test fixtures into a dedicated `testing/` module.
- Do not split a file solely to reduce line count. Split only when the resulting files each have a clear, independent responsibility.

### Comptime Enforcement
- When a value is known at compile time (literal, `comptime` parameter, enum member), prefer `comptime` validation over runtime checks.
- When a set of valid values is fixed and enumerable, use a `comptime` block with `@compileError` to enforce validity at build time. Reference: `command_catalog.zig` comptime validation block (assertCatalogParity, assertUniqueCommandNames, etc.).
- When constraints between types or modules must hold (e.g., an enum in the parser must match an enum in the store), add a `comptime` assertion that breaks the build if they diverge. Do not rely on tests alone for structural invariants.
- When a function accepts `anytype`, add `comptime` constraints using `@hasDecl`, `@hasField`, or `@typeInfo` with a clear `@compileError` message. Reference: `atomic_write.zig` reader type validation.
- Do not add comptime complexity for constraints that are naturally enforced by the type system (e.g., enum exhaustiveness in `switch`).
- Do not use comptime to generate code that is harder to read than the equivalent runtime code. Comptime is for safety, not cleverness.

### Access Scope
- `pub` is granted only when the declaration is called from outside the module. "Might be used in the future" is not a reason for `pub`.
- When reviewing, verify that every added `pub fn` / `pub const` is actually imported by another module. If there is no import site, remove `pub`.
- `store/api.zig` is a Facade and must not leak internal types, constants, or version information from `store`. When adding a new `pub` to `api.zig`, confirm that it is required by the `ops` layer.
- `pub fn` in the `ops` layer is limited to functions called from `app/cli`. Helpers used only within `ops` must not be `pub`.
- When an internal helper is needed by multiple modules, do not simply make it `pub` in place. Move it to the appropriate layer (e.g., an internal module in `store`) and expose it through the correct boundary.
- Shared test-only helpers should live under `src/testing/` rather than becoming `pub` on `store/api.zig`.
- If a Facade file accumulates test-only helpers or fixtures, move them to `src/testing/` and keep the Facade production-focused.

### Documentation Freshness
- When CLI commands, subcommands, options, or aliases change, modify the generating Zig source first and regenerate `docs/cli.md` and `docs/man/omohi.1`. Do not hand-edit generated artifacts alone.
- When the persistence layout (directory structure or file format under `.omohi`) changes, verify that `AGENTS.md` is up to date.
- When a new command or exit code is added, update `AGENTS.md` (CLI Contract).
- When domain constraints (ID generation rules, path constraints, tag constraints) change, update `AGENTS.md` (Domain Constraints).
- When testing policy or CI configuration changes, verify that `AGENTS.md` (Testing Policy) reflects the current state.
- When bash completion sources or fixtures change, update both the files under `completions/` and the corresponding tests.
- If `make docs-check` detects a diff in CI, the change is considered incomplete.

## Review Output
- Report findings first, ordered by severity, with file references.
- State assumptions and residual risks explicitly.
