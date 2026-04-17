# Test Taxonomy

This document defines the role of each test entrypoint in `omohi`.
Use it to decide where a new test belongs and what kind of breakage it should catch.

## Principles

- Fixed CI tests protect stable behavior and must stay deterministic.
- Performance checks protect baseline cost, not broad functional behavior.
- `ai-fuzz` is not a fixed regression suite. It is a local, exploratory bug-finding tool.
- `ai-fuzz` should target realistic bugs that ordinary usage can hit, not ultra-niche edge cases.

## Test Surfaces

- `make test`
  - Baseline automated verification for the repository.
  - Primary focus is store-layer correctness, plus the minimum required upper-layer coverage.

- `make test-contract`
  - Fixed CLI contract regression checks.
  - Protects parser behavior, exit codes, and public command expectations.

- `make test-reliability`
  - Fixed regression checks for reliability-sensitive behavior.
  - Focuses on LOCK handling, staged corruption, and related durability paths.

- `make test-completion`
  - Fixed regression checks for shell completion behavior.
  - Protects commands, subcommands, and public option surfaces used by completion.

- `.github/scripts/omohi_smoke.sh` / `make test-smoke`
  - Fixed smoke test for the must-not-break major command path.
  - Intended for post-merge confidence on `main`, not exploratory coverage.

- `.github/scripts/omohi_e2e_matrix.sh` / `make test-e2e-matrix`
  - Fixed end-to-end coverage for normal user scenarios.
  - Runs on a schedule and focuses on standard command patterns, aliases, parser boundaries, and common output behavior.

- `.github/scripts/omohi_perf_baseline.sh` / `make perf-baseline`
  - Minimum performance baseline checks.
  - Intended to catch large regressions in representative command cost, not broad functional behavior.

- `make docs-check`
  - Fixed generated-doc drift check.
  - Ensures CLI docs stay synchronized with generated sources.

- `make check`
  - Aggregate quality gate.
  - Intended for broader change verification across formatting, build, tests, and docs.

- `make test-ai-fuzz`
  - Fixed smoke test for the AI fuzz harness itself.
  - Verifies the harness path and artifact generation, not bug hunting.

- `make ai-fuzz`
  - Local exploratory execution of one generated or hand-written AI fuzz scenario.
  - Intended to surface bugs rather than preserve a fixed contract.

- `make ai-fuzz-generate`
  - Local scenario generation for bug-finding runs.
  - Produces scenarios that should complement fixed CI coverage rather than duplicate it.

## AI Fuzz Role

`ai-fuzz` exists to expose bugs that fixed regression suites are less likely to cover.

Desired target profile:

- plausible under ordinary or slightly-abusive real usage
- reproducible
- worth investigating by a developer
- roughly "a bug that maybe 1 out of 30 users could hit"

Good `ai-fuzz` themes:

- boundary values and near-limit inputs
- missing files and state transitions
- repeated commands and idempotency surprises
- order-sensitive workflows
- cross-command interactions such as `commit` + `tag` + `find` + `show`
- small randomized orderings or compact durability loops

Avoid using `ai-fuzz` for:

- simple happy-path regression already covered by smoke or matrix tests
- purely synthetic corner cases with little user value
- unstable scenarios that are hard to reproduce from artifacts
