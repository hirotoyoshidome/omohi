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
2. Boundary alignment: `app/cli -> ops`, and `ops -> store/api.zig`
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

## Review Output
- Report findings first, ordered by severity, with file references.
- State assumptions and residual risks explicitly.
