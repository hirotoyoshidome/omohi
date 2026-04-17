# AI Fuzz Harness

This directory contains a Docker-isolated harness for exploring `omohi` with AI-driven command sequences.
The harness treats `omohi` as a black-box CLI, installs it from GitHub Releases, and stores reproducible session artifacts on the host.

## What This Adds

- A lightweight Debian slim image that downloads the latest `omohi` release asset and runs it inside Docker.
- A host-side session runner that launches one fresh container per session.
- A container-side runner that executes a bash-based session DSL and captures step-level artifacts.
- A minimal example session and a harness smoke test.

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

## Quick Start

```sh
tools/ai-fuzz/run_session.sh tools/ai-fuzz/examples/basic_session.sh
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

## Session DSL

Session files are bash scripts sourced inside the container runner.
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
.artifacts/ai-fuzz/<timestamp>-test-harness-basic_session/
```

Remove retained harness artifacts with:

```sh
make clean-ai-fuzz
```
