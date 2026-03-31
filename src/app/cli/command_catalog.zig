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
        .usage = "track <path>",
        .summary = "Register one file or recursively track files under a directory.",
        .positionals = &.{
            .{ .name = "path", .required = true, .repeatable = false, .description = "Path to the file or directory to track." },
        },
        .options = &.{},
        .examples = &.{ "omohi track /tmp/note.txt", "omohi track ." },
        .notes = &.{
            "The store is auto-created on the first successful track.",
            "Directories are expanded recursively into tracked files. Non-regular entries are skipped.",
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
        .usage = "add <path>",
        .summary = "Stage one tracked file or recursively stage tracked files under a directory.",
        .positionals = &.{
            .{ .name = "path", .required = true, .repeatable = false, .description = "Path to the tracked file or directory to stage." },
        },
        .options = &.{},
        .examples = &.{ "omohi add /tmp/note.txt", "omohi add ." },
        .notes = &.{
            "When a directory is given, tracked files under it are staged recursively.",
            "Untracked and non-regular entries are skipped.",
        },
    },
    .{
        .name = "rm",
        .usage = "rm <path>",
        .summary = "Remove one staged file or recursively unstage staged files under a directory.",
        .positionals = &.{
            .{ .name = "path", .required = true, .repeatable = false, .description = "Path to the staged file or directory to unstage." },
        },
        .options = &.{},
        .examples = &.{ "omohi rm /tmp/note.txt", "omohi rm ." },
        .notes = &.{
            "When a directory is given, staged files under it are unstaged recursively.",
            "Untracked, non-staged, and non-regular entries are skipped.",
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
        .notes = &.{},
    },
    .{
        .name = "tracklist",
        .usage = "tracklist",
        .summary = "List tracked targets with tracked file IDs.",
        .positionals = &.{},
        .options = &.{},
        .examples = &.{"omohi tracklist"},
        .notes = &.{},
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
        .usage = "find [--tag <tag>] [--date YYYY-MM-DD]",
        .summary = "Search commits by optional tag and date filters.",
        .positionals = &.{},
        .options = &.{
            .{ .long = "tag", .short = 't', .value_name = "tag", .required = false, .repeatable = false, .description = "Filter commits by tag name." },
            .{ .long = "date", .short = 'd', .value_name = "YYYY-MM-DD", .required = false, .repeatable = false, .description = "Filter commits by local date prefix." },
        },
        .examples = &.{
            "omohi find",
            "omohi find --tag release",
            "omohi find --date 2026-03-17",
            "omohi find --tag release --date 2026-03-17",
        },
        .notes = &.{"When both filters are set, intersection is returned."},
    },
    .{
        .name = "show",
        .usage = "show <commitId>",
        .summary = "Show one commit details payload.",
        .positionals = &.{
            .{ .name = "commitId", .required = true, .repeatable = false, .description = "64-char commit ID." },
        },
        .options = &.{},
        .examples = &.{"omohi show aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
        .notes = &.{},
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
