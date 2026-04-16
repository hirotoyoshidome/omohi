---
name: omohi-platform-guard
description: Use this when changes touch std.posix, builtin.os, builtin.target, std.process.Child, or any external command invocation. Verify that the code works correctly on both Linux and macOS (the two supported platforms).
---

# omohi Platform Guard

## When to Apply
Apply this skill when a change:
- Imports or calls `std.posix` or `std.posix.system`
- References `builtin.os` or `builtin.target`
- Spawns an external process via `std.process.Child`
- Uses filesystem operations that may differ between Linux and macOS (symlink behavior, case sensitivity, extended attributes)
- Adds or modifies shell scripts in `.github/scripts/`

## Audit Procedure

1. List every `std.posix` call in the changed code.
2. For each call, verify that the POSIX function exists and behaves identically on both Linux (glibc) and macOS (libSystem).
3. For `fsync` error handling, follow the established pattern: handle `.BADF`, `.INVAL`, `.ROFS`, `.SUCCESS` explicitly. Reference: `lock.zig`, `atomic_write.zig`, `staged.zig`, `trash.zig`.
4. For external process spawning, verify:
   - The command is available in the default PATH on both platforms (e.g., `less` is standard on both).
   - A graceful fallback exists if the command is not found (`error.FileNotFound`). Reference: `pager.zig`.
   - No hardcoded absolute paths to the command (use bare command name for PATH lookup).
5. For shell scripts, verify:
   - Use `#!/usr/bin/env bash` (not `#!/bin/bash`).
   - Do not use GNU-specific flags without checking availability (e.g., `gtime` vs `/usr/bin/time`). Reference: `omohi_perf_baseline.sh` platform detection.
   - Do not assume GNU coreutils behavior for `sed`, `date`, `stat`, etc.

## Known OS-Dependent Files
The following files contain platform-specific code and are the reference for established patterns:
- `src/store/storage/lock.zig` — `getpid()`, `gethostname()`, `fsync()`
- `src/store/storage/atomic_write.zig` — `fsync()`
- `src/store/local/staged.zig` — `fsync()`
- `src/store/local/trash.zig` — `fsync()`
- `src/app/cli/runtime/terminal_color.zig` — `isatty()`
- `src/app/cli/runtime/pager.zig` — `isatty()`, `std.process.Child`
- `src/app/cli/command/version.zig` — `builtin.target`

## Guard Rules
- New code using `std.posix` must follow the error-handling pattern of the files listed above.
- New external process spawning must include a fallback for command-not-found.
- Do not introduce Linux-only syscalls (e.g., `epoll`, `inotify`, `signalfd`) or macOS-only syscalls (e.g., `kqueue` for file watching) without a platform abstraction layer.
- If a new OS-dependent behavior is unavoidable, document the platform assumption in a comment and add a CI step that covers both platforms.

## Review Output
- List each OS-dependent call found in the change.
- State whether it follows the established pattern or introduces a new pattern.
- If a new pattern is introduced, state the justification and whether CI coverage exists for both platforms.
