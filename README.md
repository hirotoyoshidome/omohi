# omohi

Build knowledge from the process, not just the result.

[日本語](./README.ja.md)

## Why Long-Term Process Preservation Matters

Many decisions make sense in the moment but become hard to recover months or years later.
Code and final outputs remain, but the reasoning path often disappears.

omohi is built to preserve that path as durable local data:
what was tracked, when it was recorded, and how it can be referenced again.

## What omohi Is

omohi is a local-first CLI for process logging.
It separates three concerns explicitly:

- Tracking: define what should be remembered.
- Recording: capture snapshots intentionally.
- Referencing: revisit history without destroying it.

## Positioning: Different Tools for Different Time Horizons

These tools are complementary:

- Git is strong for project-oriented source management (branches, diffs, collaboration workflows).
- Notion and Obsidian are strong for readable organization and short-to-mid-term note workflows.
- omohi is optimized for long-term continuity of decision process and context.

omohi does not replace those tools. It covers a different problem boundary.

## Core Philosophy

- Local-first by default.
- Preserve process, not only outcomes.
- Favor durability and explicit boundaries over convenience.
- Keep history non-destructive as a principle.
- Keep ownership with the individual user.

## Non-goals

- No web app.
- No account, authentication, or hosting.
- No core-level remote persistence or sharing.
- No Git integration as a core model.
- No branch/diff model in initial scope.

## Why CLI First

omohi is intended to be used over long spans.
CLI-first design makes it easier to embed in everyday workflows and automation.

## Install

```sh
./install.sh
```

```sh
./install.sh --prefix /custom/path --optimize ReleaseFast
```

```sh
./install.sh --skip-tests
```

## Build and Test

```sh
make build
make test
```

## Quick Command Basics

Use `docs/cli.md` as the full command reference.
Below is the minimal day-to-day flow:
Relative and absolute paths are accepted. Relative paths are resolved from your current working directory.

```sh
# 1) Start tracking a file
omohi track ./note.md

# 2) Stage current content
omohi add ./note.md

# 3) Commit with a message
omohi commit -m "capture decision background"

# 4) Check state
omohi status

# 5) Search and inspect history
omohi find --tag architecture --date 2026-03-18
omohi show <commitId>
```

Tag operations are available as:
`omohi tag add`, `omohi tag ls`, `omohi tag rm`.

## Data and Safety Highlights

- Store location: `~/.omohi`
- Persistent format is file-based local storage.
- Destructive operations are lock-protected.
- Writes follow atomic write rules for durability.

## Today and the Direction Ahead

Today, omohi focuses on reliable recording primitives.
That may feel minimal by design.

The long-term direction is to increase the value of accumulated process logs,
so long-span decision context remains usable, not forgotten.

## Documentation

- CLI reference: [docs/cli.md](./docs/cli.md)
- Japanese README: [README.ja.md](./README.ja.md)

## Contributing

Contributions are welcome, including bug reports, feature ideas, and documentation improvements.
Use GitHub Issues for proposals and reports, and check the contribution guide first.
Pull requests should be opened from topic branches based on `main`, and should target `main`.
Releases are created by tagging a commit on `main` with `vMAJOR.MINOR.PATCH`.

- Contribution guide: [CONTRIBUTING.md](./CONTRIBUTING.md)
- Code of Conduct: [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)
- Issue templates: [`.github/ISSUE_TEMPLATE`](./.github/ISSUE_TEMPLATE)

## License

This project is licensed under the MIT License. See [LICENSE](./LICENSE).
