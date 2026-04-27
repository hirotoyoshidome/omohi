# omohi CLI Reference

This file is generated from `src/app/cli/command_catalog.zig`. Do not edit manually.

## Command Summary

| Command | Usage | Summary |
| --- | --- | --- |
| `track` | `track <path>...` | Register one file or recursively track files under a directory. |
| `untrack` | `untrack (<trackedFileId> | --missing)` | Remove one tracked target by ID or clear all missing tracked targets. |
| `add` | `add [-a|--all] [<path>...]` | Stage one tracked file, a tracked directory subtree, or all changed tracked files. |
| `rm` | `rm [-a|--all] [<path>...]` | Remove one staged file, recursively unstage staged files under a directory, or unstage all staged files. |
| `commit` | `commit -m <message> [-t <tag>] [--dry-run] [--empty]` | Create a commit from staged entries. |
| `status` | `status` | Show tracked and staged state overview. |
| `tracklist` | `tracklist [--output <text|json>] [--field <id|path>]...` | List tracked targets with tracked file IDs. |
| `version` | `version` | Print application version and build target. |
| `find` | `find [--tag <tag>] [--empty|--no-empty] [--since <YYYY-MM-DD|YYYY-MM-DDTHH:MM:SS>] [--until <YYYY-MM-DD|YYYY-MM-DDTHH:MM:SS>] [--limit <1-500>] [--output <text|json>] [--field <commit_id|message|created_at>]...` | Search commits by optional tag, empty-commit, and local-time range filters. |
| `show` | `show [--output <text|json>] [--field <commit_id|message|created_at|paths|tags>]... <commitId>` | Show one commit details payload. |
| `journal` | `journal` | Show recent journal logs in reverse chronological order. |
| `tag` | `tag [--field <tag>]...` | List all known tag names. |
| `tag ls` | `tag ls [--field <tag>]... <commitId>` | List tags for one commit. |
| `tag add` | `tag add <commitId> <tagNames...>` | Attach one or more tags to a commit. |
| `tag rm` | `tag rm <commitId> <tagNames...>` | Remove one or more tags from a commit. |
| `help` | `help` | Print command usages. |

## Command Details

### track

- Usage: `omohi track <path>...`
- Summary: Register one file or recursively track files under a directory.
- Positionals:
  - `path` (required, repeatable): Path to the file or directory to track.
- Options:
  - None
- Examples:
  - `omohi track /tmp/note.txt`
  - `omohi track .`
  - `omohi track ./*.md`
- Notes:
  - The store is auto-created on the first successful track.
  - Directories are expanded recursively into tracked files. Non-regular entries are skipped.
  - Shell-expanded multiple paths are accepted and processed in order.

### untrack

- Usage: `omohi untrack (<trackedFileId> | --missing)`
- Summary: Remove one tracked target by ID or clear all missing tracked targets.
- Positionals:
  - `trackedFileId` (optional): Tracked file ID from `omohi tracklist`.
- Options:
  - `--missing` (optional): Untrack every tracked entry currently shown as `missing: <absolutePath>` in `omohi status`.
- Examples:
  - `omohi untrack 6b2f0b7309d442f6be405d9dd80e4ad8`
  - `omohi untrack --missing`
- Notes:
  - Use `omohi tracklist` to resolve IDs before untracking one specific target.
  - `--missing` removes all tracked targets that appear as `missing: <absolutePath>` in `omohi status`.
  - `<trackedFileId>` and `--missing` cannot be combined.

### add

- Usage: `omohi add [-a|--all] [<path>...]`
- Summary: Stage one tracked file, a tracked directory subtree, or all changed tracked files.
- Positionals:
  - `path` (optional, repeatable): Path to the tracked file or directory to stage.
- Options:
  - `-a`, `--all` (optional): Stage all tracked files shown as `changed: <absolutePath>` in `omohi status`.
- Examples:
  - `omohi add /tmp/note.txt`
  - `omohi add .`
  - `omohi add ./*.md`
  - `omohi add -a`
- Notes:
  - When a directory is given, tracked files under it are staged recursively.
  - `-a` and `--all` stage every tracked file currently shown as `changed: <absolutePath>` in `omohi status`.
  - Tracked files shown as `missing: <absolutePath>` in `omohi status` are not staged by `add`; resolve them with `omohi untrack --missing` when needed.
  - `-a` and explicit paths cannot be combined.
  - Untracked and non-regular entries are skipped.
  - Shell-expanded multiple paths are accepted and processed in order.

### rm

- Usage: `omohi rm [-a|--all] [<path>...]`
- Summary: Remove one staged file, recursively unstage staged files under a directory, or unstage all staged files.
- Positionals:
  - `path` (optional, repeatable): Path to the staged file or directory to unstage.
- Options:
  - `-a`, `--all` (optional): Unstage all currently staged files.
- Examples:
  - `omohi rm /tmp/note.txt`
  - `omohi rm .`
  - `omohi rm ./*.md`
  - `omohi rm -a`
- Notes:
  - When a directory is given, staged files under it are unstaged recursively.
  - `-a` and `--all` unstage every currently staged file.
  - `-a` and explicit paths cannot be combined.
  - Untracked, non-staged, and non-regular entries are skipped.
  - Shell-expanded multiple paths are accepted and processed in order.

### commit

- Usage: `omohi commit -m <message> [-t <tag>] [--dry-run] [--empty]`
- Summary: Create a commit from staged entries.
- Positionals:
  - None
- Options:
  - `-m`, `--message` `<message>` (required): Commit message text.
  - `-t`, `--tag` `<tag>` (optional, repeatable): Tag name to attach. Can be repeated.
  - `--dry-run` (optional): Show commit result preview without writing commit data.
  - `-e`, `--empty` (optional): Create a message-only commit with no staged file entries.
- Examples:
  - `omohi commit -m "initial"`
  - `omohi commit -m "release" --tag release -t prod`
  - `omohi commit -m "check" --dry-run`
  - `omohi commit --empty -m "memo"`
- Notes:
  - `-m` or `--message` is required.
  - If a file was already staged and later becomes `missing`, `commit` still uses the staged entry.
  - `--dry-run` shows such staged entries with a `(missing)` marker.
  - `--empty` creates a commit from message metadata only and leaves staged files untouched.

### status

- Usage: `omohi status`
- Summary: Show tracked and staged state overview.
- Positionals:
  - None
- Options:
  - None
- Examples:
  - `omohi status`
- Notes:
  - Human-readable text output uses one line per entry: `staged: <absolutePath>`, `changed: <absolutePath>`, or `missing: <absolutePath>`.
  - `missing` means the path is still tracked but the current file is no longer present as a regular file.
  - When `missing` appears, run `omohi untrack --missing` to clear all missing tracked targets explicitly.
  - ANSI colors are emitted only when stdout is a TTY.

### tracklist

- Usage: `omohi tracklist [--output <text|json>] [--field <id|path>]...`
- Summary: List tracked targets with tracked file IDs.
- Positionals:
  - None
- Options:
  - `--output` `<text|json>` (optional): Choose human-readable text or JSON output.
  - `--field` `<id|path>` (optional, repeatable): Select one or more fields. Repeat to keep field order.
- Examples:
  - `omohi tracklist`
  - `omohi tracklist --field id --field path`
  - `omohi tracklist --output json`
- Notes:
  - Default text output keeps the existing `<trackedFileId> <absolutePath>` line format.
  - When `--field` is set in text mode, each line contains only the selected values separated by spaces.

### version

- Usage: `omohi version`
- Summary: Print application version and build target.
- Positionals:
  - None
- Options:
  - None
- Examples:
  - `omohi version`
- Notes:
  - `-v` and `--version` aliases are also supported.

### find

- Usage: `omohi find [--tag <tag>] [--empty|--no-empty] [--since <YYYY-MM-DD|YYYY-MM-DDTHH:MM:SS>] [--until <YYYY-MM-DD|YYYY-MM-DDTHH:MM:SS>] [--limit <1-500>] [--output <text|json>] [--field <commit_id|message|created_at>]...`
- Summary: Search commits by optional tag, empty-commit, and local-time range filters.
- Positionals:
  - None
- Options:
  - `-t`, `--tag` `<tag>` (optional): Filter commits by tag name.
  - `--empty` (optional): Return only empty commits.
  - `--no-empty` (optional): Return only non-empty commits.
  - `-s`, `--since` `<YYYY-MM-DD|YYYY-MM-DDTHH:MM:SS>` (optional): Filter commits created at or after the given local date/time.
  - `-u`, `--until` `<YYYY-MM-DD|YYYY-MM-DDTHH:MM:SS>` (optional): Filter commits created at or before the given local date/time.
  - `--limit` `<1-500>` (optional): Limit the number of returned commits. Accepts integers from 1 through 500.
  - `--output` `<text|json>` (optional): Choose human-readable text or JSON output.
  - `--field` `<commit_id|message|created_at>` (optional, repeatable): Select one or more result fields. Repeat to keep field order.
- Examples:
  - `omohi find`
  - `omohi find --limit 100`
  - `omohi find --tag release`
  - `omohi find --empty`
  - `omohi find --no-empty --tag release`
  - `omohi find --since 2026-03-17`
  - `omohi find --tag release --since 2026-03-17 --until 2026-03-17T23:59:59`
  - `omohi find --field commit_id --field created_at`
  - `omohi find --output json --tag release`
- Notes:
  - When tag, empty-commit, and time filters are set, intersection is returned.
  - Date-only and datetime values are interpreted in the local timezone.
  - `--since` and `--until` are inclusive bounds.
  - `--empty` and `--no-empty` cannot be combined.
  - Without `--limit`, `find` returns up to 500 commits and pages text output on TTY with `less` when available.
  - `--limit` accepts integers from 1 through 500 and disables pager output when set.
  - Each result is shown as commit ID, local timestamp, and commit message in a multi-line block.
  - The public `created_at` field is rendered in the local timezone.

### show

- Usage: `omohi show [--output <text|json>] [--field <commit_id|message|created_at|paths|tags>]... <commitId>`
- Summary: Show one commit details payload.
- Positionals:
  - `commitId` (required): 64-char commit ID.
- Options:
  - `--output` `<text|json>` (optional): Choose human-readable text or JSON output.
  - `--field` `<commit_id|message|created_at|paths|tags>` (optional, repeatable): Select one or more fields. Repeat to keep field order.
- Examples:
  - `omohi show aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`
  - `omohi show --field commit_id --field tags aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`
  - `omohi show --output json aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`
- Notes:
  - Shows the commit ID and local timestamp first, then the commit message.
  - Lists changed file paths under `commit changes:`.
  - Omits internal IDs such as `snapshotId` and object content hashes.

### journal

- Usage: `omohi journal`
- Summary: Show recent journal logs in reverse chronological order.
- Positionals:
  - None
- Options:
  - None
- Examples:
  - `omohi journal`
- Notes:
  - Shows the latest 500 successful mutating command records.
  - Displays timestamps in the local timezone.
  - TTY output is paged with less when available.

### tag

- Usage: `omohi tag [--field <tag>]...`
- Summary: List all known tag names.
- Positionals:
  - None
- Options:
  - `--field` `<tag>` (optional, repeatable): Select one or more fields. Repeat to keep field order.
- Examples:
  - `omohi tag`
  - `omohi tag --field tag`
- Notes:
  - Lists persisted tag names in ascending order.
  - When `--field` is set, only the selected tag values are printed, one per line.
  - Use `tag ls <commitId>` to inspect tags attached to one commit.

### tag ls

- Usage: `omohi tag ls [--field <tag>]... <commitId>`
- Summary: List tags for one commit.
- Positionals:
  - `commitId` (required): 64-char commit ID.
- Options:
  - `--field` `<tag>` (optional, repeatable): Select one or more fields. Repeat to keep field order.
- Examples:
  - `omohi tag ls aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`
  - `omohi tag ls --field tag aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`
- Notes:
  - When `--field` is set, only the selected tag values are printed, one per line.

### tag add

- Usage: `omohi tag add <commitId> <tagNames...>`
- Summary: Attach one or more tags to a commit.
- Positionals:
  - `commitId` (required): 64-char commit ID.
  - `tagNames` (required, repeatable): One or more tag names to add.
- Options:
  - None
- Examples:
  - `omohi tag add aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa release prod`
- Notes:
  - None

### tag rm

- Usage: `omohi tag rm <commitId> <tagNames...>`
- Summary: Remove one or more tags from a commit.
- Positionals:
  - `commitId` (required): 64-char commit ID.
  - `tagNames` (required, repeatable): One or more tag names to remove.
- Options:
  - None
- Examples:
  - `omohi tag rm aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa prod`
- Notes:
  - None

### help

- Usage: `omohi help`
- Summary: Print command usages.
- Positionals:
  - `topic` (optional): Optional topic name.
- Options:
  - None
- Examples:
  - `omohi help`
  - `omohi help commit`
- Notes:
  - `-h` and `--help` aliases are also supported.

## Exit Codes

- `0`: success
- `2`: CLI usage error
- `3`: domain error
- `4`: use-case error
- `10`: system error
- `11`: data destroyed (reserved)

## Representative Errors

- Parse `InvalidCommand`: Invalid command. Run `omohi help` to see available commands.
- Parse `MissingArgument`: Missing required argument. Check command usage with `omohi help`.
- Parse `UnknownOption`: Unknown option. Run `omohi help` to see supported options.
- Parse `InvalidDate`: Invalid date/time input. Use YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS, and ensure --since is not later than --until.
- Runtime `NothingToCommit`: No staged files to commit.
- Runtime `OmohiNotInitialized`: Store is not initialized. Run `omohi track <path>` to create ~/.omohi.
- Runtime `CommitNotFound`: Commit not found. Check the commit ID with `omohi find`.
- Runtime `NotFound`: Target not found. Check the ID/path and try again.
- Runtime `AlreadyTracked`: The file is already tracked.
- Runtime `LockAlreadyAcquired`: Another operation is in progress because ~/.omohi/LOCK exists.
If no omohi process is running, remove ~/.omohi/LOCK manually and retry.
- Runtime `VersionMismatch`: Store version mismatch detected in ~/.omohi/VERSION.
The store may be from a different format or corrupted.
Back up ~/.omohi, then migrate or recreate the store.
- Runtime `MissingStoreVersion`: Store metadata is incomplete because ~/.omohi/VERSION is missing.
This can indicate corruption or tampering.
Back up ~/.omohi and restore VERSION before retrying.
