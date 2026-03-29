# omohi CLI Reference

This file is generated from `src/app/cli/command_catalog.zig`. Do not edit manually.

## Command Summary

| Command | Usage | Summary |
| --- | --- | --- |
| `track` | `track <path>` | Register one file or recursively track files under a directory. |
| `untrack` | `untrack <trackedFileId>` | Remove a tracked target by tracked file ID. |
| `add` | `add <path>` | Stage one tracked file or recursively stage tracked files under a directory. |
| `rm` | `rm <path>` | Remove one staged file or recursively unstage staged files under a directory. |
| `commit` | `commit -m <message> [-t <tag>] [--dry-run]` | Create a commit from staged entries. |
| `status` | `status` | Show tracked and staged state overview. |
| `tracklist` | `tracklist` | List tracked targets with tracked file IDs. |
| `version` | `version` | Print application version and build target. |
| `find` | `find [--tag <tag>] [--date YYYY-MM-DD]` | Search commits by optional tag and date filters. |
| `show` | `show <commitId>` | Show one commit details payload. |
| `tag ls` | `tag ls <commitId>` | List tags for one commit. |
| `tag add` | `tag add <commitId> <tagNames...>` | Attach one or more tags to a commit. |
| `tag rm` | `tag rm <commitId> <tagNames...>` | Remove one or more tags from a commit. |
| `help` | `help` | Print command usages. |

## Command Details

### track

- Usage: `omohi track <path>`
- Summary: Register one file or recursively track files under a directory.
- Positionals:
  - `path` (required): Path to the file or directory to track.
- Options:
  - None
- Examples:
  - `omohi track /tmp/note.txt`
  - `omohi track .`
- Notes:
  - The store is auto-created on the first successful track.
  - Directories are expanded recursively into tracked files. Non-regular entries are skipped.

### untrack

- Usage: `omohi untrack <trackedFileId>`
- Summary: Remove a tracked target by tracked file ID.
- Positionals:
  - `trackedFileId` (required): Tracked file ID from `omohi tracklist`.
- Options:
  - None
- Examples:
  - `omohi untrack 6b2f0b7309d442f6be405d9dd80e4ad8`
- Notes:
  - Use `omohi tracklist` to resolve IDs before untrack.

### add

- Usage: `omohi add <path>`
- Summary: Stage one tracked file or recursively stage tracked files under a directory.
- Positionals:
  - `path` (required): Path to the tracked file or directory to stage.
- Options:
  - None
- Examples:
  - `omohi add /tmp/note.txt`
  - `omohi add .`
- Notes:
  - When a directory is given, tracked files under it are staged recursively.
  - Untracked and non-regular entries are skipped.

### rm

- Usage: `omohi rm <path>`
- Summary: Remove one staged file or recursively unstage staged files under a directory.
- Positionals:
  - `path` (required): Path to the staged file or directory to unstage.
- Options:
  - None
- Examples:
  - `omohi rm /tmp/note.txt`
  - `omohi rm .`
- Notes:
  - When a directory is given, staged files under it are unstaged recursively.
  - Untracked, non-staged, and non-regular entries are skipped.

### commit

- Usage: `omohi commit -m <message> [-t <tag>] [--dry-run]`
- Summary: Create a commit from staged entries.
- Positionals:
  - None
- Options:
  - `-m`, `--message` `<message>` (required): Commit message text.
  - `-t`, `--tag` `<tag>` (optional, repeatable): Tag name to attach. Can be repeated.
  - `--dry-run` (optional): Show commit result preview without writing commit data.
- Examples:
  - `omohi commit -m "initial"`
  - `omohi commit -m "release" --tag release -t prod`
  - `omohi commit -m "check" --dry-run`
- Notes:
  - `-m` or `--message` is required.

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
  - None

### tracklist

- Usage: `omohi tracklist`
- Summary: List tracked targets with tracked file IDs.
- Positionals:
  - None
- Options:
  - None
- Examples:
  - `omohi tracklist`
- Notes:
  - None

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

- Usage: `omohi find [--tag <tag>] [--date YYYY-MM-DD]`
- Summary: Search commits by optional tag and date filters.
- Positionals:
  - None
- Options:
  - `-t`, `--tag` `<tag>` (optional): Filter commits by tag name.
  - `-d`, `--date` `<YYYY-MM-DD>` (optional): Filter commits by local date prefix.
- Examples:
  - `omohi find`
  - `omohi find --tag release`
  - `omohi find --date 2026-03-17`
  - `omohi find --tag release --date 2026-03-17`
- Notes:
  - When both filters are set, intersection is returned.

### show

- Usage: `omohi show <commitId>`
- Summary: Show one commit details payload.
- Positionals:
  - `commitId` (required): 64-char commit ID.
- Options:
  - None
- Examples:
  - `omohi show aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`
- Notes:
  - None

### tag ls

- Usage: `omohi tag ls <commitId>`
- Summary: List tags for one commit.
- Positionals:
  - `commitId` (required): 64-char commit ID.
- Options:
  - None
- Examples:
  - `omohi tag ls aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`
- Notes:
  - None

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
- Parse `InvalidDate`: Invalid date format. Use YYYY-MM-DD.
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
