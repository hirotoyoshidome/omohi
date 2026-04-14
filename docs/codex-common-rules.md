# Common Rules for omohi Codex

## 1. Purpose
This document defines the common rules for `omohi` implementation requests to reduce repeated follow-up requests.  
The intended workflow is "a normal request message + a reference to this document"; a fixed request template is not required.

## 2. Scope
* In scope: design, implementation, and review requests under `omohi`
* Out of scope: individual tasks unrelated to `omohi`

## 3. MUST

### 3.1 Read Reference Materials
* Always read the materials specified in the request before starting implementation.
* If multiple materials are provided, state their priority explicitly and resolve any inconsistencies.
* If there are directories or files that will not be referenced, explicitly mark them as excluded.

### 3.2 Layer Boundaries and Dependency Direction
* `ops` must not import other `ops`; shared behavior needed by multiple ops must be moved into `store`.
* When `ops` references `store`, access is allowed only through `store/api.zig` (Facade).
* Upper layers must not depend directly on the internal implementation of lower layers.
* Whenever adding an import, always verify that it does not break the dependency direction.

### 3.3 File Placement
* Procedures (use cases and operations) must be placed under `ops`.
* Persistence and storage responsibilities must be placed under `store/storage` (or another explicitly designated persistence directory).
* Intermediate responsibilities such as local file operations must be separated into an explicitly designated directory (for example, `store/local`).
* Do not mix implementations with different responsibilities in the same file.

### 3.4 Public Boundary (Keep `api` Thin)
* Keep `api.zig` focused on public functions, and do not expose internal constants, internal types, or internal version information.
* Definitions that do not need to be exposed to upper layers must be hidden in internal modules.
* Do not treat conceptually different versions as the same constant (for example, a persistence version and a journal version).

### 3.5 Naming and Concept Consistency
* Use names that accurately reflect responsibility; avoid vague generic terms and suffixes that are likely to collide.
* Do not force DDD-derived terminology when it would create confusion.
* Directory names must clearly constrain their purpose; avoid names that can become catch-all buckets.

### 3.6 Update Tests at the Same Time
* When adding functionality, splitting responsibilities, or moving code, add or update the related tests at the same time.
* For changes with regression risk, explicitly state the verification points for each changed area.

### 3.7 Diff Consistency
* Confirm that the "design intent" matches the actual file placement and dependencies.
* If a rule violation is pointed out, re-check related areas across the codebase to avoid missing similar issues.

### 3.8 CLI Contract Changes Must Update All Surfaces
* Do not treat a CLI change as complete after updating only parser code, only command execution, or only docs.
* When commands, subcommands, aliases, options, or option values change, verify and update every affected public surface in the same change:
  * parser behavior and argument structs
  * command catalog / help text / allowed values
  * shell completion sources and completion test fixtures
  * CLI-facing tests that cover the changed contract
* If user-facing CLI docs are generated, update the generating Zig source first and then regenerate the docs.
* If completion is hand-maintained, update the completion source and its tests explicitly rather than assuming docs regeneration will cover it.

## 4. SHOULD
* Split files with high cognitive load by responsibility.
* For persistence structures, define structs and types before using them.
* Leave short comments or explanations near the implementation to capture design intent.
* Do not carry temporary PoC-driven structures into the production implementation.

## 5. Prohibited
* Direct imports from one `ops` module into another `ops` module
* Direct imports from `ops` into internal `store` modules
* Redefining or leaking internal details in the public layer (`api.zig`)
* Directory placement that does not match responsibility (for example, putting procedures under `store`)
* Starting implementation without reading the reference materials specified in the request
* Cross-cutting refactors without tests
* Declaring a CLI contract change finished while completion or CLI-facing regression tests are knowingly stale

## 6. Minimal Additions to a Request (Not a Template)
Add only the following one or two lines to a normal request message.

```text
Common rules: Always refer to omohi/codex/codex-common-rules.md and implement on the assumption that there are no MUST violations.
Scope: (target path for this request) / Excluded: (paths not to touch in this request)
```

## 7. Checklist for Plan Review
* Are the reference materials and excluded scope explicitly stated?
* Are layer dependencies (the Facade boundary) preserved?
* Do placement and naming match the intended responsibilities?
* Is the public boundary of `api.zig` kept thin?
* Does the plan include adding or updating tests?
* If the change touches CLI behavior, does the plan explicitly mention command catalog, completion, and CLI-facing tests?

## 8. Update Policy
* If the same issue causes repeated follow-up requests two or more times, promote it into either MUST or SHOULD and add it here.
* Whenever the rules are changed, leave a one- or two-line note explaining why.
