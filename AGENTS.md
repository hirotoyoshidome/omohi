# AGENTS.md

This document defines execution guidelines for agents working on `omohi`.
The scope is based on specification, implementation, and philosophy documents under `omohi/`.
Agents should also refer to directories under `docs/` when they are relevant to the task.

## 0. Purpose
- `omohi` is a **local-first infrastructure** for handling the process of thinking.
- It explicitly separates tracking / recording / referencing instead of acting as a generic note tool.
- Design priorities are: durability, clear boundaries, and long-term consistency over convenience.

## 1. Non-goals
- Do not build a web version.
- Do not provide accounts, authentication, or hosting.
- Do not provide core-level data sharing or remote persistence.
- Do not design around Git integration (this is not a Git replacement).
- Do not include branching or diff display in the initial scope.
- Do not optimize toward an “all-in-one convenience tool.”

## 2. Technical Policy
- Use Zig.
- Minimize external dependencies (no CLI framework dependency).
- Use local files for persistence (no RDB).
- Use UTF-8 / LF / case-sensitive handling.
- Target OS: Linux, macOS (Windows is out of initial scope).
- Target architectures: x86_64, arm64.

## 3. Architectural Boundaries
- Layer structure:
  - `app/cli` (argument interpretation, output formatting)
  - `ops` (procedural operations)
  - `store` (core: persistence + constraints)
  - `testing` (shared test-only fixtures and support; outside the production dependency graph)
- Dependency direction:
  - Production code: `app/cli -> ops -> store`
  - `store` must not depend on upper layers.
  - `ops` must not depend on other `ops`; shared behavior used by multiple ops must move into `store`.
  - Production code must not depend on `testing`; `testing` may depend on lower-layer internals for tests only.
- Expose `store` only through the Facade (`store/api.zig`).
- Avoid unnecessary abstraction; abstract only where required.
- DI policy:
  - Static DI (comptime) is allowed.
  - Dynamic DI (including vtable style) is disallowed by default.

## 4. CLI Contract (Must Preserve)
- Target commands:
  - `track`, `untrack`, `add`, `rm`, `commit`, `status`, `tracklist`, `find`, `show`, `tag ls`, `tag add`, `tag rm`, `help`
- Parser behavior:
  - Resolve commands by longest match (including subcommands).
  - Support `--key=value`, `--key value`, and `-k value`.
  - Treat tokens after `--` as positional args.
- Exit codes:
  - `0` success
  - `2` CLI usage error
  - `3` domain error
  - `4` use-case error
  - `10` system error
  - `11` data destroyed (reserved for recovery guidance)
- Do not change existing message contracts without clear intent.

## 5. Domain Constraints
- Use SHA-256 (64-char hex) for hashes.
- ID generation:
  - `ContentHash = SHA-256(Base64(fileBytes))`
  - `StagedFileId = SHA-256("<contentHash>:<absolutePath>")`
  - `SnapshotId = SHA-256(concatenated "<path>:<contentHash>" sorted by path)`
  - `CommitId = SHA-256("<snapshotId>:<message>:<createdAt>")`
  - `TrackedFileId = UUIDv4 without hyphens (32-char hex)`
- Path constraints:
  - absolute path only
  - must not contain `..`
  - non-empty
- Tag constraints:
  - non-empty
  - max length 255

## 6. Persistence Rules
- Root is `~/.omohi` (single user-level store, not project-level).
- Do not create an `init` command; auto-create on first `track`.
- All writes must use Atomic Write:
  - `fsync(file) -> rename -> fsync(parent dir)`
- In-place overwrite is prohibited.
- Deletion should be logical deletion via `.trash` (GC is future work).
- Destructive commands must require LOCK (read operations do not).
- LOCK must be created atomically with create-if-not-exists semantics.
- In `commit`, update `HEAD` last so completion is anchored by `HEAD`.

## 7. `.omohi` Layout Highlights
- `tracked/<TrackedFileId>`: tracked targets (content is absolute path)
- `staged/entries/<StagedFileId>`: staging metadata
- `staged/objects/<ContentHash>`: temporary full copy created at add-time
- `objects/<2-char-prefix>/<ContentHash>`: committed content
- `snapshots/<2-char-prefix>/<SnapshotId>`
- `commits/<2-char-prefix>/<CommitId>`
- `data/tags/<TagName>`
- `data/commit-tags/<2-char-prefix>/<CommitId>`
- `journal/`, `VERSION`, `LOCK`, `HEAD`

## 8. Critical Implementation Rules
- Create `staged/objects` at `add` time (not at `commit` time).
- Do not delete `objects/commits/snapshots` by default.
- Increment `VERSION` only when the data structure changes.
- Persist timestamps in UTC; display in system timezone.
- Keep the fixed millisecond timestamp format.
- Add a short comment above non-trivial functions. Public functions must follow the Zig documentation rules, and internal helper functions should still have a brief intent comment unless trivial.
- When a file is generated from Zig sources or templates, modify the generator/source (`.zig`, templates, catalog data) first; do not hand-edit the generated artifact alone.
- Naming rules:
  - Do not use `save` (too ambiguous).
  - Define `update` at field/column granularity.
  - Do not create generic bucket names such as `core`, `util`, `common`, `support`, `kernel`.

## 9. Testing Policy
- Highest priority: `store` layer.
- `ops` / `app/cli`: minimum required tests.
- Focus on destructive operations, ID generation, persistence consistency, and exit-code regressions.
- Put shared test-only fixtures, inspectors, and failure-injection helpers under `src/testing/`.
- Do not expose test-only helpers through `store/api.zig`; keep the Facade focused on production knowledge required by `ops`.
- CI split:
  - `main-smoke`: keep this limited to the must-not-break CLI path for major commands after merge to `main`.
  - `e2e-matrix`: use this for broad CLI pattern coverage, including option combinations, aliases, parser boundaries, output modes, no-op cases, and regression scenarios.
  - `perf-baseline`: performance-only; do not place functional E2E coverage there.
- When command behavior, options, aliases, or output contracts change:
  - Update `main-smoke` only if the change affects the must-not-break major-command path.
  - Update `e2e-matrix` when the change adds or changes CLI patterns, parser combinations, or output contracts that should remain covered over time.
- Accept intentional overlap between smoke and matrix tests when it reduces maintenance cost and keeps the major-command path obvious.

## 10. Change Decision Criteria
- First, check alignment with philosophy (local-first / process logging / non-destructive).
- Second, verify boundaries (`app/cli -> ops -> store`) are preserved.
- Third, verify external contracts (CLI behavior, exit codes, persistence format) are preserved.
- If uncertain, prioritize durability and explicit design.

## 11. Change Verification Checklist
- Confirm the change delivers the intended behavior.
- Ensure all relevant tests pass. Use `make test` as the default baseline, and run broader checks when the change touches related contracts.
- Run `make test-smoke` when changing the must-not-break major-command path or post-merge smoke coverage.
- Run `make test-e2e-matrix` when changing CLI options, parser behavior, aliases, output formats, or broad command-pattern coverage.
- Ensure Bash Completion still works. Use `make test-completion` when commands, subcommands, or options may be affected.
- If commands, subcommands, or options are added or changed, update completion behavior accordingly.
- Treat CLI contract changes as multi-surface updates. When commands, subcommands, aliases, or options are added or changed, verify all affected sources together before finishing:
  - parser behavior and argument structs
  - command catalog / help text / allowed values
  - completion sources and completion test fixtures
  - smoke / matrix / contract tests that cover the changed public behavior
- Do not mark a CLI change complete after updating only the parser or only the docs. Completion and CLI-facing tests must be checked in the same change when they are in scope.
- Avoid introducing significant performance regressions. When behavior may affect command cost or traversal size, verify that performance is not materially worse.
- If commands, subcommands, or options are added or changed, update the generating Zig sources first and then regenerate the user-facing CLI docs:
  - `docs/cli.md`
  - `docs/man/omohi.1`
- If completion is driven by a hand-maintained source or test fixture rather than generated docs, update that source directly and keep it in sync with the command catalog.
- Ensure formatting is applied. Use `make fmt-check` at minimum.
- Prefer `make check` when the change scope is broad enough to affect multiple quality gates.
