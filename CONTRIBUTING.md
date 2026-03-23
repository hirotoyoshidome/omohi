# Contributing to omohi

Thanks for your interest in contributing.
Bug reports, feature ideas, and documentation improvements are all welcome.

## Code of Conduct

Please review [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) before participating.

## How to Contribute

- Open a GitHub Issue for bugs, proposals, or questions.
- Use the Issue templates when possible.
- Keep reports concrete and reproducible.

## What to Report

- Bug reports:
  - Incorrect behavior, crashes, unexpected errors, data consistency concerns.
- Feature requests:
  - New commands, workflow improvements, or better long-term usability.
- Documentation improvements:
  - Gaps, ambiguity, or wording issues in README and docs.

## Before Opening an Issue

- Search existing Issues to avoid duplicates.
- Confirm the behavior on the latest main branch if possible.
- Collect enough context so maintainers can reproduce the problem.

## Issue Quality Checklist

- Clear summary of the problem.
- Expected behavior and actual behavior.
- Reproduction steps.
- Environment details:
  - OS and architecture.
  - `omohi version` output if available.
- Logs or command output that help diagnosis.

## Pull Requests

- Prefer small, focused changes.
- If behavior changes, include or update tests when applicable.
- If user-facing behavior changes, update related docs.
- Keep changes aligned with project constraints and boundaries.

## Branch Strategy

- `main` is the default branch and the primary integration branch.
- Create topic branches from `main`.
- Open pull requests against `main`.
- Prefer branch names such as `feature/<name>`, `fix/<name>`, or `docs/<name>`.
- Keep pull requests small so they are easier to review and merge.

## Release Flow

- Releases are cut from commits already merged into `main`.
- Create a Git tag in `vMAJOR.MINOR.PATCH` format for the commit you want to release.
- Pushing that tag triggers the GitHub release workflow.
- Treat tags as the release boundary. `main` may move ahead of the latest released tag.

## Project Principles to Respect

- Local-first design.
- Non-destructive persistence direction.
- Explicit boundaries: `app/cli -> ops -> store`.
- Favor durability and clarity over convenience.
