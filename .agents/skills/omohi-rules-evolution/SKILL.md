---
name: omohi-rules-evolution
description: Use this after a review or implementation reveals a recurring pattern, a new constraint, or a rule gap. Evaluate whether the finding should be promoted into the project's AI reference files to prevent recurrence.
---

# omohi Rules Evolution

## When to Apply
Apply this skill when any of the following occur:
- The same review finding appears in two or more separate changes.
- A new architectural constraint or platform behavior is discovered that is not documented.
- An existing rule is found to be outdated, incorrect, or incomplete.
- A comptime guard, dependency rule, or test pattern is established that should be followed by future changes.

## Evaluation Criteria
Before updating a reference file, confirm the following:
1. The finding is **not ephemeral** (it applies beyond the current task).
2. The finding is **not already covered** by an existing rule (search AGENTS.md, Zig-coding-rules.md, codex-common-rules.md, and all SKILL.md files first).
3. The finding is **actionable** (it can be stated as a concrete rule, not a vague preference).

## Target Files and Their Scope

| File | What to add |
|------|-------------|
| `AGENTS.md` | Architecture, CLI contracts, persistence rules, domain constraints, testing policy, change criteria |
| `docs/Zig-coding-rules.md` | Zig language-level design rules, ownership patterns, API design, comptime patterns |
| `docs/codex-common-rules.md` | Cross-cutting implementation rules, MUST/SHOULD/Prohibited items, checklist items |
| `.agents/skills/*/SKILL.md` | Skill-specific review viewpoints, audit procedures, checklists |

## Update Procedure
1. Identify which file is the correct home for the new rule based on the table above.
2. State the rule concisely. Follow the existing style of the target file.
3. If the rule originated from a repeated issue, add a one-line note explaining the trigger (following `codex-common-rules.md` §8 Update Policy).
4. Check that the new rule does not contradict existing rules. If it supersedes an old rule, update or remove the old one.
5. After updating, verify the rule is consistent with related skills and reference documents.

## What NOT to Add
- One-time fixes or task-specific workarounds.
- Rules that duplicate what the type system or comptime already enforces.
- Subjective style preferences without a concrete rationale.
- Information derivable from git history or the current code.
