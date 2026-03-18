# Contributing to omohi

Thanks for your interest in contributing.
Bug reports, feature ideas, and documentation improvements are all welcome.

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

## Project Principles to Respect

- Local-first design.
- Non-destructive persistence direction.
- Explicit boundaries: `app/cli -> ops -> store`.
- Favor durability and clarity over convenience.
