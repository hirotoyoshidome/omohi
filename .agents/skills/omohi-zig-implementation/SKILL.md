---
name: omohi-zig-implementation
description: Use this for omohi Zig implementation tasks (design, implementation, fixes, refactors, and adding tests). Do not embed the specification text into the skill; read the designated materials each time before implementing. Decide ownership, lifetime, allocator policy, error policy, and public boundaries first, then implement in accordance with Zig-coding-rules and omohi common rules.
---

# omohi Zig Implementation Rules

## Required Reading
Before implementing, always read the following.

1. `docs/Zig-coding-rules.md`
2. `docs/codex-common-rules.md`
3. Only the parts relevant to the task
   - `codex-md/`

## Decide Before Implementing
Before writing code, determine the following.

1. Ownership: `borrowed` / `owned` / `arena-managed`
2. Lifetime: what the return value depends on (arguments / allocator / arena / static)
3. Allocator policy: caller-managed or local-managed
4. Error policy: propagate with `try`, or convert/substitute with `catch`
5. Public boundary: whether `pub` is kept to a minimum
6. Import impact: whether it breaks dependency direction

## Implementation Rules
- Do not use `anyerror` routinely.
- Do not swallow failures with `catch`.
- Do not return `[]u8` / `[]const u8` with ambiguous ownership.
- Confine `@ptrCast` / `*anyopaque` to boundaries.
- As a rule, do not use dynamic DI (vtable / `*anyopaque`).
- Do not import one `ops` module from another `ops` module; move shared behavior into `store`.
- References from `ops -> store` must go only through `store/api.zig`.
- Prefer whole-system optimization over local optimization.
- Judge changes by their impact on architectural boundaries, durability, clarity, and testability, not only by local simplification or micro-performance.
- As a rule, write comments for functions.
- For `pub` functions, follow the documentation rules in `docs/Zig-coding-rules.md`. For internal functions, leave a short comment unless the function is trivial and self-evident.
- If a function exists only for tests, add a marker comment immediately above it using the format `// TEST-ONLY: <reason>`.

## Change Completion Criteria
- State the referenced materials and the excluded scope explicitly.
- Confirm that the design intent matches the file placement and dependency direction.
- Add or update related tests at the same time.
- State any unresolved risks explicitly.
