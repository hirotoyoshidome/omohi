# AGENTS.md

This document defines execution guidelines for agents working on `omohi`.
The scope is based on specification, implementation, and philosophy documents under `omohi/`.

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
- Dependency direction:
  - `app/cli -> ops -> store`
  - `store` must not depend on upper layers.
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
  - `CommitId = SHA-256("<snapshotId>:<message>")`
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
- Naming rules:
  - Do not use `save` (too ambiguous).
  - Define `update` at field/column granularity.
  - Do not create generic bucket names such as `core`, `util`, `common`, `support`, `kernel`.

## 9. Testing Policy
- Highest priority: `store` layer.
- `ops` / `app/cli`: minimum required tests.
- Focus on destructive operations, ID generation, persistence consistency, and exit-code regressions.

## 10. Change Decision Criteria
- First, check alignment with philosophy (local-first / process logging / non-destructive).
- Second, verify boundaries (`app/cli -> ops -> store`) are preserved.
- Third, verify external contracts (CLI behavior, exit codes, persistence format) are preserved.
- If uncertain, prioritize durability and explicit design.
