# AI Fuzz Harness

This directory contains a Docker-isolated harness for exploring `omohi` with AI-driven command sequences.
The harness treats `omohi` as a black-box CLI, installs it from GitHub Releases, and stores reproducible session artifacts on the host.

## What This Adds

- A lightweight Debian slim image that downloads the latest `omohi` release asset and runs it inside Docker.
- A host-side session runner that launches one fresh container per session.
- A container-side runner that executes a bash-based session DSL and captures step-level artifacts.
- Reusable scenarios, a scenario template, and a harness smoke test.

`omohi` itself is unchanged.
All reporting is produced by this harness, not by the CLI.

## Release Source

By default the Docker image installs `hirotoyoshidome/omohi` from the latest GitHub Release.
You can pin a specific tag during build if needed:

```sh
docker build \
  --build-arg OMOHI_RELEASE=v0.1.0 \
  --file tools/ai-fuzz/Dockerfile \
  -t omohi-ai-fuzz:local .
```

## Layout

- `scenarios/`: canonical scenario files for AI-driven runs
- `scenarios/smoke_basic.sh`: fixed smoke scenario for harness validation
- `scenarios/template.sh`: starting point for new scenarios
- `generate_scenario.sh`: AI-backed scenario generator
- `run_session.sh`: low-level runner for one scenario file
- `test_harness.sh`: smoke-test entrypoint used by `make test-ai-fuzz`
- `../../docs/test-taxonomy.md`: test role definitions, including the intended role of `ai-fuzz`

## Quick Start

```sh
make ai-fuzz-generate
make ai-fuzz SCENARIO=tools/ai-fuzz/scenarios/<generated-name>.sh
```

Artifacts are written to:

```text
.artifacts/ai-fuzz/<timestamp>-<session-name>/
```

The most useful files are:

- `SUMMARY.md`
- `session.json`
- `findings.json`
- `steps/NNN-stdout.txt`
- `steps/NNN-stderr.txt`

## Standard Workflow

1. Generate a scenario with `make ai-fuzz-generate`.
2. Review or tweak the generated file under `tools/ai-fuzz/scenarios/` if needed.
3. Run the scenario with `make ai-fuzz SCENARIO=tools/ai-fuzz/scenarios/<name>.sh`.
4. Review `.artifacts/ai-fuzz/<timestamp>-<scenario>/SUMMARY.md` first, then inspect `findings.json` and `steps/*` as needed.
5. Remove retained artifacts with `make clean-ai-fuzz` when they are no longer needed.

## Scenario Generation

The generator checks whether `codex` or `claude` is installed, reads the current AI fuzz harness context plus relevant docs/source context, and asks the selected AI to produce one scenario file.

Common commands:

```sh
make ai-fuzz-generate
make ai-fuzz-generate PROMPT='Exercise tag operations around empty commits'
make ai-fuzz-generate NAME=tag_empty_commit PROMPT='Exercise tag operations around empty commits'
make ai-fuzz-generate AI=claude
make ai-fuzz-generate FORCE=1 NAME=tag_empty_commit
```

Behavior:

- If `AI` is omitted, the generator prefers `codex` and falls back to `claude`.
- If `PROMPT` is omitted, the AI acts as a beginner bug hunter and chooses one useful bug-finding angle from the current implementation and docs context.
- If `NAME` is omitted, the AI chooses the scenario basename and the generator normalizes it.
- If the destination file already exists, generation fails unless `FORCE=1` is set.
- Generated scenarios are validated with `bash -n` before the command succeeds.

Default scenario intent:

- bug-finding over happy-path regression
- boundary values and near-limit inputs
- missing files and state transitions
- repeated commands and idempotency surprises
- order-sensitive workflows
- cross-command interactions such as `commit` + `tag` + `find` + `show`
- compact durability or repetition checks when they stay reproducible

The target is not an ultra-niche corner case.
Aim for plausible bugs that ordinary or slightly-abusive usage could hit.

## Scenario Naming

- Reusable scenarios checked into the repo should use descriptive names such as `track_empty_commit.sh`.
- Smoke-only scenarios should use the `smoke_*.sh` prefix.
- Temporary scenarios created by AI can live in `tools/ai-fuzz/scenarios/` during investigation and may be deleted after use if they are not worth keeping.

## Session DSL

Scenario files are bash scripts sourced inside the container runner.
Use the provided helpers instead of calling commands directly.

Helpers:

- `session_name "<name>"`
- `set_step_timeout <seconds>`
- `work_path "<relative-path>"`
- `file_write "<relative-path>" "<content>"`
- `file_append "<relative-path>" "<content>"`
- `file_delete "<relative-path>"`
- `file_mkdir "<relative-path>"`
- `file_move "<from>" "<to>"`
- `omohi_exec <args...>`
- `omohi_exec_expect "<csv-exit-codes>" <args...>`
- `shell_exec "<command>"`
- `shell_exec_expect "<csv-exit-codes>" "<command>"`
- `capture_commit_id <var-name>`

The file helpers only accept relative paths under the container work root.
Use `work_path` when you need an absolute path to pass into `omohi`.

Generated scenarios should follow the same rules:

- Start with `#!/usr/bin/env bash`
- Set `session_name` and `set_step_timeout`
- Use only the documented DSL helpers
- Keep file operations under the container work root
- Use `*_expect` helpers for intentional failures

## Test Role

`ai-fuzz` is not the main fixed regression layer.

- Fixed regression responsibility belongs to the normal CI-oriented test surfaces.
- `ai-fuzz` is a local, exploratory bug-finding tool.
- The intended taxonomy for all test surfaces is documented in [docs/test-taxonomy.md](../../docs/test-taxonomy.md).

## Finding Heuristics

The v1 heuristics flag:

- timed out steps
- unexpected exit codes relative to the helper expectation
- signal-style exit statuses
- stderr markers such as `panic`, `segmentation fault`, or `assertion failed`

The goal is recall, not perfect precision.
Review `SUMMARY.md` first, then inspect the per-step logs.

## Host Requirements

- Docker Engine
- Bash
- Internet access for `docker build`, because the image downloads release assets from GitHub

## Test

```sh
make test-ai-fuzz
```

`make test-ai-fuzz` keeps its smoke-test artifacts under:

```text
.artifacts/ai-fuzz/<timestamp>-test-harness-smoke_basic/
```

Remove retained harness artifacts with:

```sh
make clean-ai-fuzz
```

If you need the low-level runner directly, this remains supported:

```sh
tools/ai-fuzz/run_session.sh tools/ai-fuzz/scenarios/<name>.sh
```
