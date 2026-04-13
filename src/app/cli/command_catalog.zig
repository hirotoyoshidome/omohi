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

const ParsedRequestTag = std.meta.Tag(parser_types.ParsedRequest);

pub const public_command_tags = [_]ParsedRequestTag{
    .track,
    .untrack,
    .add,
    .rm,
    .commit,
    .status,
    .tracklist,
    .version,
    .find,
    .show,
    .journal,
    .tag_ls,
    .tag_add,
    .tag_rm,
    .help,
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
        .usage = "untrack (<trackedFileId> | --missing)",
        .summary = "Remove one tracked target by ID or clear all missing tracked targets.",
        .positionals = &.{
            .{ .name = "trackedFileId", .required = false, .repeatable = false, .description = "Tracked file ID from `omohi tracklist`." },
        },
        .options = &.{
            .{ .long = "missing", .short = null, .value_name = null, .required = false, .repeatable = false, .description = "Untrack every tracked entry currently shown as `missing: <absolutePath>` in `omohi status`." },
        },
        .examples = &.{
            "omohi untrack 6b2f0b7309d442f6be405d9dd80e4ad8",
            "omohi untrack --missing",
        },
        .notes = &.{
            "Use `omohi tracklist` to resolve IDs before untracking one specific target.",
            "`--missing` removes all tracked targets that appear as `missing: <absolutePath>` in `omohi status`.",
            "`<trackedFileId>` and `--missing` cannot be combined.",
        },
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
            "Tracked files shown as `missing: <absolutePath>` in `omohi status` are not staged by `add`; resolve them with `omohi untrack --missing` when needed.",
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
        .usage = "commit -m <message> [-t <tag>] [--dry-run] [--empty]",
        .summary = "Create a commit from staged entries.",
        .positionals = &.{},
        .options = &.{
            .{ .long = "message", .short = 'm', .value_name = "message", .required = true, .repeatable = false, .description = "Commit message text." },
            .{ .long = "tag", .short = 't', .value_name = "tag", .required = false, .repeatable = true, .description = "Tag name to attach. Can be repeated." },
            .{ .long = "dry-run", .short = null, .value_name = null, .required = false, .repeatable = false, .description = "Show commit result preview without writing commit data." },
            .{ .long = "empty", .short = 'e', .value_name = null, .required = false, .repeatable = false, .description = "Create a message-only commit with no staged file entries." },
        },
        .examples = &.{
            "omohi commit -m \"initial\"",
            "omohi commit -m \"release\" --tag release -t prod",
            "omohi commit -m \"check\" --dry-run",
            "omohi commit --empty -m \"memo\"",
        },
        .notes = &.{
            "`-m` or `--message` is required.",
            "If a file was already staged and later becomes `missing`, `commit` still uses the staged entry.",
            "`--dry-run` shows such staged entries with a `(missing)` marker.",
            "`--empty` creates a commit from message metadata only and leaves staged files untouched.",
        },
    },
    .{
        .name = "status",
        .usage = "status",
        .summary = "Show tracked and staged state overview.",
        .positionals = &.{},
        .options = &.{},
        .examples = &.{"omohi status"},
        .notes = &.{
            "Human-readable text output uses one line per entry: `staged: <absolutePath>`, `changed: <absolutePath>`, or `missing: <absolutePath>`.",
            "`missing` means the path is still tracked but the current file is no longer present as a regular file.",
            "When `missing` appears, run `omohi untrack --missing` to clear all missing tracked targets explicitly.",
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
        .usage = "find [--tag <tag>] [--empty|--no-empty] [--since <YYYY-MM-DD|YYYY-MM-DDTHH:MM:SS>] [--until <YYYY-MM-DD|YYYY-MM-DDTHH:MM:SS>] [--limit <1-500>] [--output <text|json>] [--field <commit_id|message|created_at>]...",
        .summary = "Search commits by optional tag, empty-commit, and local-time range filters.",
        .positionals = &.{},
        .options = &.{
            .{ .long = "tag", .short = 't', .value_name = "tag", .required = false, .repeatable = false, .description = "Filter commits by tag name." },
            .{ .long = "empty", .short = null, .value_name = null, .required = false, .repeatable = false, .description = "Return only empty commits." },
            .{ .long = "no-empty", .short = null, .value_name = null, .required = false, .repeatable = false, .description = "Return only non-empty commits." },
            .{ .long = "since", .short = 's', .value_name = "YYYY-MM-DD|YYYY-MM-DDTHH:MM:SS", .required = false, .repeatable = false, .description = "Filter commits created at or after the given local date/time." },
            .{ .long = "until", .short = 'u', .value_name = "YYYY-MM-DD|YYYY-MM-DDTHH:MM:SS", .required = false, .repeatable = false, .description = "Filter commits created at or before the given local date/time." },
            .{ .long = "limit", .short = null, .value_name = "1-500", .required = false, .repeatable = false, .description = "Limit the number of returned commits. Accepts integers from 1 through 500." },
            .{ .long = "output", .short = null, .value_name = "text|json", .required = false, .repeatable = false, .description = "Choose human-readable text or JSON output." },
            .{ .long = "field", .short = null, .value_name = "commit_id|message|created_at", .required = false, .repeatable = true, .description = "Select one or more result fields. Repeat to keep field order." },
        },
        .examples = &.{
            "omohi find",
            "omohi find --limit 100",
            "omohi find --tag release",
            "omohi find --empty",
            "omohi find --no-empty --tag release",
            "omohi find --since 2026-03-17",
            "omohi find --tag release --since 2026-03-17 --until 2026-03-17T23:59:59",
            "omohi find --field commit_id --field created_at",
            "omohi find --output json --tag release",
        },
        .notes = &.{
            "When tag, empty-commit, and time filters are set, intersection is returned.",
            "Date-only and datetime values are interpreted in the local timezone.",
            "`--since` and `--until` are inclusive bounds.",
            "`--empty` and `--no-empty` cannot be combined.",
            "Without `--limit`, `find` returns up to 500 commits and pages text output on TTY with `less` when available.",
            "`--limit` accepts integers from 1 through 500 and disables pager output when set.",
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

comptime {
    @setEvalBranchQuota(10_000);
    assertCatalogParity();
    assertUniqueCommandNames();
    assertUniqueOptionNames();
    assertOutputValueSpecs();
    assertFieldValueSpecs();
}

// Returns the public catalog name for a parsed request tag.
fn commandNameForTag(tag: ParsedRequestTag) []const u8 {
    return switch (tag) {
        .tag_ls => "tag ls",
        .tag_add => "tag add",
        .tag_rm => "tag rm",
        else => @tagName(tag),
    };
}

// Verifies that the public command list matches the catalog order and excludes internal commands.
fn assertCatalogParity() void {
    if (all.len != public_command_tags.len) {
        @compileError("command catalog and public parser command list must have the same length");
    }

    for (public_command_tags, 0..) |tag, idx| {
        const expected_name = commandNameForTag(tag);
        if (!std.mem.eql(u8, all[idx].name, expected_name)) {
            @compileError(std.fmt.comptimePrint(
                "command catalog name mismatch at index {d}: expected '{s}', found '{s}'",
                .{ idx, expected_name, all[idx].name },
            ));
        }
    }
}

// Verifies that public command names are globally unique.
fn assertUniqueCommandNames() void {
    for (all, 0..) |lhs, lhs_idx| {
        for (all, 0..) |rhs, rhs_idx| {
            if (lhs_idx == rhs_idx) continue;
            if (std.mem.eql(u8, lhs.name, rhs.name)) {
                @compileError(std.fmt.comptimePrint("duplicate command name: '{s}'", .{lhs.name}));
            }
        }
    }
}

// Verifies that each command has unique long and short option names with consistent value declarations.
fn assertUniqueOptionNames() void {
    for (all) |spec| {
        for (spec.options, 0..) |lhs, lhs_idx| {
            if (lhs.long.len == 0) {
                @compileError(std.fmt.comptimePrint("command '{s}' has an option with an empty long name", .{spec.name}));
            }
            if ((lhs.value_name != null) != optionTakesValue(spec.name, lhs.long)) {
                @compileError(std.fmt.comptimePrint(
                    "command '{s}' option '--{s}' value declaration does not match parser behavior",
                    .{ spec.name, lhs.long },
                ));
            }

            for (spec.options, 0..) |rhs, rhs_idx| {
                if (lhs_idx == rhs_idx) continue;
                if (std.mem.eql(u8, lhs.long, rhs.long)) {
                    @compileError(std.fmt.comptimePrint(
                        "command '{s}' declares duplicate long option '--{s}'",
                        .{ spec.name, lhs.long },
                    ));
                }
                if (lhs.short != null and rhs.short != null and lhs.short.? == rhs.short.?) {
                    @compileError(std.fmt.comptimePrint(
                        "command '{s}' declares duplicate short option '-{c}'",
                        .{ spec.name, lhs.short.? },
                    ));
                }
            }
        }
    }
}

// Verifies that output option value_name strings match the output format enum.
fn assertOutputValueSpecs() void {
    assertOptionValueSpecForCommand("tracklist", "output", parser_types.OutputFormat);
    assertOptionValueSpecForCommand("find", "output", parser_types.OutputFormat);
    assertOptionValueSpecForCommand("show", "output", parser_types.OutputFormat);
}

// Verifies that field option value_name strings match the corresponding field enums.
fn assertFieldValueSpecs() void {
    assertOptionValueSpecForCommand("tracklist", "field", parser_types.TracklistField);
    assertOptionValueSpecForCommand("find", "field", parser_types.FindField);
    assertOptionValueSpecForCommand("show", "field", parser_types.ShowField);
}

// Verifies that a command option's allowed values match an enum's tag names.
fn assertOptionValueSpecForCommand(comptime command_name: []const u8, comptime option_long: []const u8, comptime EnumType: type) void {
    const spec = commandSpecByName(command_name);
    const option = optionSpecByLong(spec, option_long);
    const value_name = option.value_name orelse @compileError(std.fmt.comptimePrint(
        "command '{s}' option '--{s}' must declare a value_name",
        .{ command_name, option_long },
    ));
    assertDelimitedValuesMatchEnum(value_name, EnumType, command_name, option_long);
}

// Returns the command spec with the given public name.
fn commandSpecByName(comptime command_name: []const u8) CommandSpec {
    for (all) |spec| {
        if (std.mem.eql(u8, spec.name, command_name)) return spec;
    }
    @compileError(std.fmt.comptimePrint("missing command catalog entry for '{s}'", .{command_name}));
}

// Returns the option spec with the given long name within one command.
fn optionSpecByLong(comptime spec: CommandSpec, comptime option_long: []const u8) OptionArgSpec {
    for (spec.options) |opt| {
        if (std.mem.eql(u8, opt.long, option_long)) return opt;
    }
    @compileError(std.fmt.comptimePrint(
        "missing option '--{s}' in command '{s}'",
        .{ option_long, spec.name },
    ));
}

// Verifies a `foo|bar|baz` value_name against an enum's tag names.
fn assertDelimitedValuesMatchEnum(
    comptime value_name: []const u8,
    comptime EnumType: type,
    comptime command_name: []const u8,
    comptime option_long: []const u8,
) void {
    const fields = std.meta.fields(EnumType);
    var iter = std.mem.splitScalar(u8, value_name, '|');
    var idx: usize = 0;
    while (iter.next()) |part| : (idx += 1) {
        if (idx >= fields.len) {
            @compileError(std.fmt.comptimePrint(
                "command '{s}' option '--{s}' declares too many values in '{s}'",
                .{ command_name, option_long, value_name },
            ));
        }
        if (!std.mem.eql(u8, part, fields[idx].name)) {
            @compileError(std.fmt.comptimePrint(
                "command '{s}' option '--{s}' value mismatch at index {d}: expected '{s}', found '{s}'",
                .{ command_name, option_long, idx, fields[idx].name, part },
            ));
        }
    }
    if (idx != fields.len) {
        @compileError(std.fmt.comptimePrint(
            "command '{s}' option '--{s}' value list count mismatch for '{s}'",
            .{ command_name, option_long, value_name },
        ));
    }
}

// Reports whether a public command option should take a value according to parser behavior.
fn optionTakesValue(comptime command_name: []const u8, comptime option_long: []const u8) bool {
    if (std.mem.eql(u8, command_name, "untrack") and std.mem.eql(u8, option_long, "missing")) return false;
    if (std.mem.eql(u8, command_name, "add") and std.mem.eql(u8, option_long, "all")) return false;
    if (std.mem.eql(u8, command_name, "commit") and std.mem.eql(u8, option_long, "dry-run")) return false;
    if (std.mem.eql(u8, command_name, "commit") and std.mem.eql(u8, option_long, "empty")) return false;
    if (std.mem.eql(u8, command_name, "commit") and std.mem.eql(u8, option_long, "message")) return true;
    if (std.mem.eql(u8, command_name, "commit") and std.mem.eql(u8, option_long, "tag")) return true;
    if (std.mem.eql(u8, command_name, "tracklist") and std.mem.eql(u8, option_long, "output")) return true;
    if (std.mem.eql(u8, command_name, "tracklist") and std.mem.eql(u8, option_long, "field")) return true;
    if (std.mem.eql(u8, command_name, "find") and std.mem.eql(u8, option_long, "tag")) return true;
    if (std.mem.eql(u8, command_name, "find") and std.mem.eql(u8, option_long, "empty")) return false;
    if (std.mem.eql(u8, command_name, "find") and std.mem.eql(u8, option_long, "no-empty")) return false;
    if (std.mem.eql(u8, command_name, "find") and std.mem.eql(u8, option_long, "since")) return true;
    if (std.mem.eql(u8, command_name, "find") and std.mem.eql(u8, option_long, "until")) return true;
    if (std.mem.eql(u8, command_name, "find") and std.mem.eql(u8, option_long, "limit")) return true;
    if (std.mem.eql(u8, command_name, "find") and std.mem.eql(u8, option_long, "output")) return true;
    if (std.mem.eql(u8, command_name, "find") and std.mem.eql(u8, option_long, "field")) return true;
    if (std.mem.eql(u8, command_name, "show") and std.mem.eql(u8, option_long, "output")) return true;
    if (std.mem.eql(u8, command_name, "show") and std.mem.eql(u8, option_long, "field")) return true;
    @compileError(std.fmt.comptimePrint(
        "missing parser option behavior mapping for command '{s}' option '--{s}'",
        .{ command_name, option_long },
    ));
}

test "command catalog public command order matches parser tags" {
    try std.testing.expectEqual(@as(usize, public_command_tags.len), all.len);
    try std.testing.expectEqualStrings("tag ls", commandNameForTag(.tag_ls));
    try std.testing.expectEqualStrings("tag add", commandNameForTag(.tag_add));
    try std.testing.expectEqualStrings("tag rm", commandNameForTag(.tag_rm));
}

test "command catalog excludes internal complete command from public list" {
    for (public_command_tags) |tag| {
        try std.testing.expect(tag != .complete);
    }
}
