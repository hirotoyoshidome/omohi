---
name: omohi-dependency-guard
description: Use this to prevent violations of omohi's dependency direction, Facade boundary, and placement responsibilities. Apply it whenever adding imports, moving files, changing public boundaries, or performing cross-cutting refactors, and preserve the rules of `app/cli -> ops` and `ops -> store/api.zig`.
---

# omohi Dependency Guard

## Dependency Direction
Always preserve the following.

- `app/cli -> ops`
- `ops -> store/api.zig`
- `store` must not depend on upper layers.
- References from `ops` to `store` must go only through `store/api.zig`.

## Placement Responsibilities
- Put procedures (use cases and operations) in `ops/`.
- Put shared persistence logic in `store/storage/`.
- Put local file operations in `store/local/`.
- Keep `store/api.zig` focused on public functions and do not leak internal details.

## Audit Procedure
Do the following before and after the change.

1. List the added imports.
2. Check that there is no dependency-direction violation.
3. Check that there is no placement-responsibility violation.
4. Check that nothing unnecessary is exposed through `api.zig`.

If there is a violation, do not proceed with implementation; revise it into a split that satisfies the boundaries.

## Naming Guard
- Do not create catch-all directory names with unclear purpose (for example: `core`, `util`, `common`, `support`, `kernel`).
- Do not use generic names with ambiguous responsibilities.

## Tests And Consistency
- When splitting responsibilities or moving files, update the related tests at the same time.
- Leave a short note describing the reason for the change and the design intent.
