const std = @import("std");
const parser_types = @import("parser/types.zig");

pub const PositionalArgSpec = struct {
    name: []const u8,
    required: bool,
    repeatable: bool,
    description: []const u8,
};

pub const OptionArgSpec = struct {
    long: []const u8,
    short: ?u8,
    value_name: ?[]const u8,
    required: bool,
    repeatable: bool,
    description: []const u8,
};

pub const CommandSpec = struct {
    name: []const u8,
    usage: []const u8,
    summary: []const u8,
    positionals: []const PositionalArgSpec,
    options: []const OptionArgSpec,
    examples: []const []const u8,
    notes: []const []const u8,
};

pub const all = [_]CommandSpec{
    .{
        .name = "track",
        .usage = "track <path>...",
        .summary = "Register one file or recursively track files under a directory.",
        .positionals = &.{
            .{ .name = "path", .required = true, .repeatable = true, .description = "Path to the file or directory to track." },
        },
        .options = &.{},
        .examples = &.{ "omohi track /tmp/note.txt", "omohi track .", "omohi track ./*.md" },
        .notes = &.{
            "The store is auto-created on the first successful track.",
            "Directories are expanded recursively into tracked files. Non-regular entries are skipped.",
            "Shell-expanded multiple paths are accepted and processed in order.",
        },
    },
    .{
        .name = "untrack",
        .usage = "untrack <trackedFileId>",
        .summary = "Remove a tracked target by tracked file ID.",
        .positionals = &.{
            .{ .name = "trackedFileId", .required = true, .repeatable = false, .description = "Tracked file ID from `omohi tracklist`." },
        },
        .options = &.{},
        .examples = &.{"omohi untrack 6b2f0b7309d442f6be405d9dd80e4ad8"},
        .notes = &.{"Use `omohi tracklist` to resolve IDs before untrack."},
    },
    .{
        .name = "add",
        .usage = "add [-a|--all] [<path>...]",
        .summary = "Stage one tracked file, a tracked directory subtree, or all changed tracked files.",
        .positionals = &.{
            .{ .name = "path", .required = false, .repeatable = true, .description = "Path to the tracked file or directory to stage." },
        },
        .options = &.{
            .{ .long = "all", .short = 'a', .value_name = null, .required = false, .repeatable = false, .description = "Stage all tracked files shown as `changed: <absolutePath>` in `omohi status`." },
        },
        .examples = &.{ "omohi add /tmp/note.txt", "omohi add .", "omohi add ./*.md", "omohi add -a" },
        .notes = &.{
            "When a directory is given, tracked files under it are staged recursively.",
            "`-a` and `--all` stage every tracked file currently shown as `changed: <absolutePath>` in `omohi status`.",
            "`-a` and explicit paths cannot be combined.",
            "Untracked and non-regular entries are skipped.",
            "Shell-expanded multiple paths are accepted and processed in order.",
        },
    },
    .{
        .name = "rm",
        .usage = "rm <path>...",
        .summary = "Remove one staged file or recursively unstage staged files under a directory.",
        .positionals = &.{
            .{ .name = "path", .required = true, .repeatable = true, .description = "Path to the staged file or directory to unstage." },
        },
        .options = &.{},
        .examples = &.{ "omohi rm /tmp/note.txt", "omohi rm .", "omohi rm ./*.md" },
        .notes = &.{
            "When a directory is given, staged files under it are unstaged recursively.",
            "Untracked, non-staged, and non-regular entries are skipped.",
            "Shell-expanded multiple paths are accepted and processed in order.",
        },
    },
    .{
        .name = "commit",
        .usage = "commit -m <message> [-t <tag>] [--dry-run]",
        .summary = "Create a commit from staged entries.",
        .positionals = &.{},
        .options = &.{
            .{ .long = "message", .short = 'm', .value_name = "message", .required = true, .repeatable = false, .description = "Commit message text." },
            .{ .long = "tag", .short = 't', .value_name = "tag", .required = false, .repeatable = true, .description = "Tag name to attach. Can be repeated." },
            .{ .long = "dry-run", .short = null, .value_name = null, .required = false, .repeatable = false, .description = "Show commit result preview without writing commit data." },
        },
        .examples = &.{
            "omohi commit -m \"initial\"",
            "omohi commit -m \"release\" --tag release -t prod",
            "omohi commit -m \"check\" --dry-run",
        },
        .notes = &.{"`-m` or `--message` is required."},
    },
    .{
        .name = "status",
        .usage = "status",
        .summary = "Show tracked and staged state overview.",
        .positionals = &.{},
        .options = &.{},
        .examples = &.{"omohi status"},
        .notes = &.{
            "Human-readable text output uses one line per entry: `staged: <absolutePath>` or `changed: <absolutePath>`.",
            "ANSI colors are emitted only when stdout is a TTY.",
        },
    },
    .{
        .name = "tracklist",
        .usage = "tracklist [--output <text|json>] [--field <id|path>]...",
        .summary = "List tracked targets with tracked file IDs.",
        .positionals = &.{},
        .options = &.{
            .{ .long = "output", .short = null, .value_name = "text|json", .required = false, .repeatable = false, .description = "Choose human-readable text or JSON output." },
            .{ .long = "field", .short = null, .value_name = "id|path", .required = false, .repeatable = true, .description = "Select one or more fields. Repeat to keep field order." },
        },
        .examples = &.{ "omohi tracklist", "omohi tracklist --field id --field path", "omohi tracklist --output json" },
        .notes = &.{
            "Default text output keeps the existing `<trackedFileId> <absolutePath>` line format.",
            "When `--field` is set in text mode, each line contains only the selected values separated by spaces.",
        },
    },
    .{
        .name = "version",
        .usage = "version",
        .summary = "Print application version and build target.",
        .positionals = &.{},
        .options = &.{},
        .examples = &.{"omohi version"},
        .notes = &.{"`-v` and `--version` aliases are also supported."},
    },
    .{
        .name = "find",
        .usage = "find [--tag <tag>] [--date YYYY-MM-DD] [--output <text|json>] [--field <commit_id|message|created_at>]...",
        .summary = "Search commits by optional tag and date filters.",
        .positionals = &.{},
        .options = &.{
            .{ .long = "tag", .short = 't', .value_name = "tag", .required = false, .repeatable = false, .description = "Filter commits by tag name." },
            .{ .long = "date", .short = 'd', .value_name = "YYYY-MM-DD", .required = false, .repeatable = false, .description = "Filter commits by local date prefix." },
            .{ .long = "output", .short = null, .value_name = "text|json", .required = false, .repeatable = false, .description = "Choose human-readable text or JSON output." },
            .{ .long = "field", .short = null, .value_name = "commit_id|message|created_at", .required = false, .repeatable = true, .description = "Select one or more result fields. Repeat to keep field order." },
        },
        .examples = &.{
            "omohi find",
            "omohi find --tag release",
            "omohi find --date 2026-03-17",
            "omohi find --tag release --date 2026-03-17",
            "omohi find --field commit_id --field created_at",
            "omohi find --output json --tag release",
        },
        .notes = &.{
            "When both filters are set, intersection is returned.",
            "Each result is shown as commit ID, local timestamp, and commit message in a multi-line block.",
            "The public `created_at` field is rendered in the local timezone.",
        },
    },
    .{
        .name = "show",
        .usage = "show [--output <text|json>] [--field <commit_id|message|created_at|paths|tags>]... <commitId>",
        .summary = "Show one commit details payload.",
        .positionals = &.{
            .{ .name = "commitId", .required = true, .repeatable = false, .description = "64-char commit ID." },
        },
        .options = &.{
            .{ .long = "output", .short = null, .value_name = "text|json", .required = false, .repeatable = false, .description = "Choose human-readable text or JSON output." },
            .{ .long = "field", .short = null, .value_name = "commit_id|message|created_at|paths|tags", .required = false, .repeatable = true, .description = "Select one or more fields. Repeat to keep field order." },
        },
        .examples = &.{
            "omohi show aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "omohi show --field commit_id --field tags aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "omohi show --output json aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        },
        .notes = &.{
            "Shows the commit ID and local timestamp first, then the commit message.",
            "Lists changed file paths under `commit changes:`.",
            "Omits internal IDs such as `snapshotId` and object content hashes.",
        },
    },
    .{
        .name = "journal",
        .usage = "journal",
        .summary = "Show recent journal logs in reverse chronological order.",
        .positionals = &.{},
        .options = &.{},
        .examples = &.{"omohi journal"},
        .notes = &.{
            "Shows the latest 500 successful mutating command records.",
            "TTY output is paged with less when available.",
        },
    },
    .{
        .name = "tag ls",
        .usage = "tag ls <commitId>",
        .summary = "List tags for one commit.",
        .positionals = &.{
            .{ .name = "commitId", .required = true, .repeatable = false, .description = "64-char commit ID." },
        },
        .options = &.{},
        .examples = &.{"omohi tag ls aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
        .notes = &.{},
    },
    .{
        .name = "tag add",
        .usage = "tag add <commitId> <tagNames...>",
        .summary = "Attach one or more tags to a commit.",
        .positionals = &.{
            .{ .name = "commitId", .required = true, .repeatable = false, .description = "64-char commit ID." },
            .{ .name = "tagNames", .required = true, .repeatable = true, .description = "One or more tag names to add." },
        },
        .options = &.{},
        .examples = &.{"omohi tag add aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa release prod"},
        .notes = &.{},
    },
    .{
        .name = "tag rm",
        .usage = "tag rm <commitId> <tagNames...>",
        .summary = "Remove one or more tags from a commit.",
        .positionals = &.{
            .{ .name = "commitId", .required = true, .repeatable = false, .description = "64-char commit ID." },
            .{ .name = "tagNames", .required = true, .repeatable = true, .description = "One or more tag names to remove." },
        },
        .options = &.{},
        .examples = &.{"omohi tag rm aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa prod"},
        .notes = &.{},
    },
    .{
        .name = "help",
        .usage = "help",
        .summary = "Print command usages.",
        .positionals = &.{
            .{ .name = "topic", .required = false, .repeatable = false, .description = "Optional topic name." },
        },
        .options = &.{},
        .examples = &.{ "omohi help", "omohi help commit" },
        .notes = &.{"`-h` and `--help` aliases are also supported."},
    },
};

// Reports whether the catalog contains a command with the exact internal name.
fn hasCommandName(name: []const u8) bool {
    for (all) |spec| {
        if (std.mem.eql(u8, spec.name, name)) return true;
    }
    return false;
}

test "command catalog command names are unique" {
    for (all, 0..) |lhs, lhs_idx| {
        for (all, 0..) |rhs, rhs_idx| {
            if (lhs_idx == rhs_idx) continue;
            try std.testing.expect(!std.mem.eql(u8, lhs.name, rhs.name));
        }
    }
}

test "command catalog includes every public parser command" {
    try std.testing.expect(hasCommandName("track"));
    try std.testing.expect(hasCommandName("untrack"));
    try std.testing.expect(hasCommandName("add"));
    try std.testing.expect(hasCommandName("rm"));
    try std.testing.expect(hasCommandName("commit"));
    try std.testing.expect(hasCommandName("status"));
    try std.testing.expect(hasCommandName("tracklist"));
    try std.testing.expect(hasCommandName("version"));
    try std.testing.expect(hasCommandName("find"));
    try std.testing.expect(hasCommandName("show"));
    try std.testing.expect(hasCommandName("journal"));
    try std.testing.expect(hasCommandName("tag ls"));
    try std.testing.expect(hasCommandName("tag add"));
    try std.testing.expect(hasCommandName("tag rm"));
    try std.testing.expect(hasCommandName("help"));
    try std.testing.expectEqual(@as(usize, 15), all.len);

    // Internal parser-only commands may exist, but they must not leak into the public catalog.
    const parsed_field_count = std.meta.fields(parser_types.ParsedRequest).len;
    try std.testing.expect(parsed_field_count >= all.len);
}
