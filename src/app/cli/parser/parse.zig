const std = @import("std");
const types = @import("types.zig");
const scan = @import("scan.zig");
const date_validation = @import("../validation/date.zig");

// Parses CLI argv tokens into a typed request; commit requests may allocate owned tag slices.
pub fn parseArgs(allocator: std.mem.Allocator, argv: []const []const u8) !types.ParsedRequest {
    if (argv.len == 0) return .{ .help = .{ .topic = null } };

    if (scan.equalsIgnoreAsciiCase(argv[0], "-h") or scan.equalsIgnoreAsciiCase(argv[0], "--help")) {
        return try parseHelp(argv[1..]);
    }

    if (scan.equalsIgnoreAsciiCase(argv[0], "-v") or scan.equalsIgnoreAsciiCase(argv[0], "--version")) {
        return try parseNoArgsCommand(.version, argv[1..]);
    }

    if (scan.equalsIgnoreAsciiCase(argv[0], "help")) {
        return try parseHelp(argv[1..]);
    }

    if (std.mem.eql(u8, argv[0], "__complete")) {
        return try parseComplete(argv[1..]);
    }

    if (std.mem.eql(u8, argv[0], "tag")) {
        if (argv.len == 1) return try parseNoArgsCommand(.tag, argv[1..]);
        if (std.mem.eql(u8, argv[1], "ls")) return try parseTagLs(argv[2..]);
        if (std.mem.eql(u8, argv[1], "add")) return try parseTagAdd(argv[2..]);
        if (std.mem.eql(u8, argv[1], "rm")) return try parseTagRm(argv[2..]);
        return error.InvalidCommand;
    }

    if (std.mem.eql(u8, argv[0], "track")) return try parseTrack(argv[1..]);
    if (std.mem.eql(u8, argv[0], "untrack")) return try parseUntrack(argv[1..]);
    if (std.mem.eql(u8, argv[0], "add")) return try parseAdd(argv[1..]);
    if (std.mem.eql(u8, argv[0], "rm")) return try parseRm(argv[1..]);
    if (std.mem.eql(u8, argv[0], "commit")) return try parseCommit(allocator, argv[1..]);
    if (std.mem.eql(u8, argv[0], "status")) return try parseNoArgsCommand(.status, argv[1..]);
    if (std.mem.eql(u8, argv[0], "tracklist")) return try parseTracklist(allocator, argv[1..]);
    if (std.mem.eql(u8, argv[0], "version")) return try parseNoArgsCommand(.version, argv[1..]);
    if (std.mem.eql(u8, argv[0], "find")) return try parseFind(allocator, argv[1..]);
    if (std.mem.eql(u8, argv[0], "show")) return try parseShow(allocator, argv[1..]);
    if (std.mem.eql(u8, argv[0], "journal")) return try parseJournal(argv[1..]);

    return error.InvalidCommand;
}

// Parses `help` arguments and accepts at most one optional topic.
fn parseHelp(args: []const []const u8) !types.ParsedRequest {
    if (args.len == 0) return .{ .help = .{ .topic = null } };
    if (args.len == 1) return .{ .help = .{ .topic = args[0] } };
    return error.UnexpectedArgument;
}

// Parses the hidden completion command and requires `--index` before `--`.
fn parseComplete(args: []const []const u8) !types.ParsedRequest {
    var index: ?usize = null;
    var stop_option = false;
    var idx: usize = 0;
    while (idx < args.len) : (idx += 1) {
        const token = args[idx];

        if (!stop_option and scan.isDoubleDash(token)) {
            stop_option = true;
            idx += 1;
            break;
        }

        if (!stop_option) {
            if (scan.parseLongOption(token)) |opt| {
                if (scan.equalsIgnoreAsciiCase(opt.key, "index")) {
                    const value = try scan.optionValue(args, &idx, opt.value);
                    index = std.fmt.parseInt(usize, value, 10) catch return error.InvalidArgument;
                    continue;
                }
                return error.UnknownOption;
            }
        }

        return error.UnexpectedArgument;
    }

    if (!stop_option) return error.MissingArgument;

    const words = args[idx..];
    const index_value = index orelse return error.MissingArgument;
    if (words.len == 0) return error.MissingArgument;
    if (index_value >= words.len) return error.InvalidArgument;

    return .{ .complete = .{
        .index = index_value,
        .words = words,
    } };
}

// Parses commands that accept no additional positional arguments.
fn parseNoArgsCommand(comptime tag: anytype, args: []const []const u8) !types.ParsedRequest {
    if (args.len != 0) return error.UnexpectedArgument;
    return @unionInit(types.ParsedRequest, @tagName(tag), {});
}

// Parses `track <path>...`.
fn parseTrack(args: []const []const u8) !types.ParsedRequest {
    if (args.len == 0) return error.MissingArgument;
    return .{ .track = .{ .paths = args } };
}

// Parses `tracklist` options for output formatting and field selection.
fn parseTracklist(allocator: std.mem.Allocator, args: []const []const u8) !types.ParsedRequest {
    var fields = std.array_list.Managed(types.TracklistField).init(allocator);
    errdefer fields.deinit();

    var output: types.OutputFormat = .text;
    var idx: usize = 0;
    var stop_option = false;
    while (idx < args.len) : (idx += 1) {
        const token = args[idx];

        if (!stop_option and scan.isDoubleDash(token)) {
            stop_option = true;
            continue;
        }

        if (!stop_option) {
            if (scan.parseLongOption(token)) |opt| {
                if (scan.equalsIgnoreAsciiCase(opt.key, "output")) {
                    const value = try scan.optionValue(args, &idx, opt.value);
                    output = try parseOutputFormat(value);
                    continue;
                }

                if (scan.equalsIgnoreAsciiCase(opt.key, "field")) {
                    const value = try scan.optionValue(args, &idx, opt.value);
                    try fields.append(try parseTracklistField(value));
                    continue;
                }

                return error.UnknownOption;
            }
        }

        return error.UnexpectedArgument;
    }

    return .{ .tracklist = .{
        .output = output,
        .fields = try fields.toOwnedSlice(),
    } };
}

// Parses `untrack <trackedFileId>` and `untrack --missing`.
fn parseUntrack(args: []const []const u8) !types.ParsedRequest {
    var missing = false;
    var tracked_file_id: ?[]const u8 = null;
    var stop_option = false;

    for (args) |token| {
        if (!stop_option and scan.isDoubleDash(token)) {
            stop_option = true;
            continue;
        }

        if (!stop_option) {
            if (scan.parseLongOption(token)) |opt| {
                if (scan.equalsIgnoreAsciiCase(opt.key, "missing")) {
                    if (opt.value != null) return error.UnknownOption;
                    if (missing or tracked_file_id != null) return error.UnexpectedArgument;
                    missing = true;
                    continue;
                }
                return error.UnknownOption;
            }
        }

        if (tracked_file_id != null or missing) return error.UnexpectedArgument;
        tracked_file_id = token;
    }

    if (!missing and tracked_file_id == null) return error.MissingArgument;
    return .{ .untrack = .{
        .tracked_file_id = tracked_file_id,
        .missing = missing,
    } };
}

// Parses `add <path>...` and `add -a|--all`.
fn parseAdd(args: []const []const u8) !types.ParsedRequest {
    var all = false;
    var idx: usize = 0;
    var stop_option = false;
    var positional_start: ?usize = null;

    while (idx < args.len) : (idx += 1) {
        const token = args[idx];

        if (!stop_option and scan.isDoubleDash(token)) {
            stop_option = true;
            if (positional_start == null) positional_start = idx + 1;
            continue;
        }

        if (!stop_option) {
            if (scan.parseLongOption(token)) |opt| {
                if (scan.equalsIgnoreAsciiCase(opt.key, "all")) {
                    if (opt.value != null) return error.UnknownOption;
                    if (all) return error.UnexpectedArgument;
                    all = true;
                    continue;
                }
                return error.UnknownOption;
            }

            if (scan.isShortOption(token, 'a')) {
                if (all) return error.UnexpectedArgument;
                all = true;
                continue;
            }
        }

        if (positional_start == null) positional_start = idx;
    }

    const paths = if (positional_start) |start| args[start..] else &.{};
    if (all) {
        if (paths.len != 0) return error.UnexpectedArgument;
        return .{ .add = .{ .all = true, .paths = paths } };
    }

    if (paths.len == 0) return error.MissingArgument;
    return .{ .add = .{ .all = false, .paths = paths } };
}

// Parses `rm <path>...` and `rm -a|--all`.
fn parseRm(args: []const []const u8) !types.ParsedRequest {
    var all = false;
    var idx: usize = 0;
    var stop_option = false;
    var positional_start: ?usize = null;

    while (idx < args.len) : (idx += 1) {
        const token = args[idx];

        if (!stop_option and scan.isDoubleDash(token)) {
            stop_option = true;
            if (positional_start == null) positional_start = idx + 1;
            continue;
        }

        if (!stop_option) {
            if (scan.parseLongOption(token)) |opt| {
                if (scan.equalsIgnoreAsciiCase(opt.key, "all")) {
                    if (opt.value != null) return error.UnknownOption;
                    if (all) return error.UnexpectedArgument;
                    all = true;
                    continue;
                }
                return error.UnknownOption;
            }

            if (scan.isShortOption(token, 'a')) {
                if (all) return error.UnexpectedArgument;
                all = true;
                continue;
            }
        }

        if (positional_start == null) positional_start = idx;
    }

    const paths = if (positional_start) |start| args[start..] else &.{};
    if (all) {
        if (paths.len != 0) return error.UnexpectedArgument;
        return .{ .rm = .{ .all = true, .paths = paths } };
    }

    if (paths.len == 0) return error.MissingArgument;
    return .{ .rm = .{ .all = false, .paths = paths } };
}

// Parses `journal` with no extra arguments.
fn parseJournal(args: []const []const u8) !types.ParsedRequest {
    if (args.len != 0) return error.UnexpectedArgument;
    return .{ .journal = .{} };
}

// Parses `tag ls <commitId>`.
fn parseTagLs(args: []const []const u8) !types.ParsedRequest {
    if (args.len != 1) return error.MissingArgument;
    return .{ .tag_ls = .{ .commit_id = args[0] } };
}

// Parses `tag add <commitId> <tagNames...>`.
fn parseTagAdd(args: []const []const u8) !types.ParsedRequest {
    if (args.len < 2) return error.MissingArgument;
    return .{ .tag_add = .{
        .commit_id = args[0],
        .tag_names = args[1..],
    } };
}

// Parses `tag rm <commitId> <tagNames...>`.
fn parseTagRm(args: []const []const u8) !types.ParsedRequest {
    if (args.len < 2) return error.MissingArgument;
    return .{ .tag_rm = .{
        .commit_id = args[0],
        .tag_names = args[1..],
    } };
}

// Parses commit options and returns owned tag storage that callers must release via `deinitParsedRequest`.
fn parseCommit(allocator: std.mem.Allocator, args: []const []const u8) !types.ParsedRequest {
    var message: ?[]const u8 = null;
    var dry_run = false;
    var empty = false;
    var tags = std.array_list.Managed([]const u8).init(allocator);
    errdefer tags.deinit();

    var idx: usize = 0;
    var stop_option = false;
    while (idx < args.len) : (idx += 1) {
        const token = args[idx];

        if (!stop_option and scan.isDoubleDash(token)) {
            stop_option = true;
            continue;
        }

        if (!stop_option) {
            if (scan.parseLongOption(token)) |opt| {
                if (scan.equalsIgnoreAsciiCase(opt.key, "dry-run")) {
                    if (opt.value != null) return error.UnknownOption;
                    dry_run = true;
                    continue;
                }

                if (scan.equalsIgnoreAsciiCase(opt.key, "empty")) {
                    if (opt.value != null) return error.UnknownOption;
                    empty = true;
                    continue;
                }

                if (scan.equalsIgnoreAsciiCase(opt.key, "message")) {
                    message = try scan.optionValue(args, &idx, opt.value);
                    continue;
                }

                if (scan.equalsIgnoreAsciiCase(opt.key, "tag")) {
                    try tags.append(try scan.optionValue(args, &idx, opt.value));
                    continue;
                }

                return error.UnknownOption;
            }
        }

        if (!stop_option and std.mem.startsWith(u8, token, "-") and token.len > 1) {
            if (scan.isShortOption(token, 'e')) {
                empty = true;
                continue;
            }

            if (scan.isShortOption(token, 'm')) {
                message = try scan.optionValue(args, &idx, null);
                continue;
            }

            if (scan.isShortOption(token, 't')) {
                try tags.append(try scan.optionValue(args, &idx, null));
                continue;
            }

            return error.UnknownOption;
        }

        return error.UnexpectedArgument;
    }

    const message_value = message orelse return error.MissingArgument;
    const tag_view = try tags.toOwnedSlice();

    return .{ .commit = .{
        .message = message_value,
        .tags = tag_view,
        .dry_run = dry_run,
        .empty = empty,
    } };
}

// Parses `find` options and validates any provided local-time range filters.
fn parseFind(allocator: std.mem.Allocator, args: []const []const u8) !types.ParsedRequest {
    var tag_name: ?[]const u8 = null;
    var empty_filter: types.FindEmptyFilter = .all;
    var since: ?[]const u8 = null;
    var until: ?[]const u8 = null;
    var since_millis: ?i64 = null;
    var until_millis: ?i64 = null;
    var limit: ?usize = null;
    var output: types.OutputFormat = .text;
    var fields = std.array_list.Managed(types.FindField).init(allocator);
    errdefer fields.deinit();

    var idx: usize = 0;
    var stop_option = false;
    while (idx < args.len) : (idx += 1) {
        const token = args[idx];

        if (!stop_option and scan.isDoubleDash(token)) {
            stop_option = true;
            continue;
        }

        if (!stop_option) {
            if (scan.parseLongOption(token)) |opt| {
                if (scan.equalsIgnoreAsciiCase(opt.key, "tag")) {
                    tag_name = try scan.optionValue(args, &idx, opt.value);
                    continue;
                }

                if (scan.equalsIgnoreAsciiCase(opt.key, "empty")) {
                    if (opt.value != null) return error.UnknownOption;
                    if (empty_filter == .non_empty_only) return error.InvalidArgument;
                    empty_filter = .empty_only;
                    continue;
                }

                if (scan.equalsIgnoreAsciiCase(opt.key, "no-empty")) {
                    if (opt.value != null) return error.UnknownOption;
                    if (empty_filter == .empty_only) return error.InvalidArgument;
                    empty_filter = .non_empty_only;
                    continue;
                }

                if (scan.equalsIgnoreAsciiCase(opt.key, "since")) {
                    const value = try scan.optionValue(args, &idx, opt.value);
                    since_millis = try date_validation.parseFindBoundaryMillis(value, .since);
                    since = value;
                    continue;
                }

                if (scan.equalsIgnoreAsciiCase(opt.key, "until")) {
                    const value = try scan.optionValue(args, &idx, opt.value);
                    until_millis = try date_validation.parseFindBoundaryMillis(value, .until);
                    until = value;
                    continue;
                }

                if (scan.equalsIgnoreAsciiCase(opt.key, "output")) {
                    const value = try scan.optionValue(args, &idx, opt.value);
                    output = try parseOutputFormat(value);
                    continue;
                }

                if (scan.equalsIgnoreAsciiCase(opt.key, "field")) {
                    const value = try scan.optionValue(args, &idx, opt.value);
                    try fields.append(try parseFindField(value));
                    continue;
                }

                if (scan.equalsIgnoreAsciiCase(opt.key, "limit")) {
                    const value = try scan.optionValue(args, &idx, opt.value);
                    limit = try parseFindLimit(value);
                    continue;
                }

                return error.UnknownOption;
            }
        }

        if (!stop_option and std.mem.startsWith(u8, token, "-") and token.len > 1) {
            if (scan.isShortOption(token, 't')) {
                tag_name = try scan.optionValue(args, &idx, null);
                continue;
            }
            if (scan.isShortOption(token, 's')) {
                const value = try scan.optionValue(args, &idx, null);
                since_millis = try date_validation.parseFindBoundaryMillis(value, .since);
                since = value;
                continue;
            }
            if (scan.isShortOption(token, 'u')) {
                const value = try scan.optionValue(args, &idx, null);
                until_millis = try date_validation.parseFindBoundaryMillis(value, .until);
                until = value;
                continue;
            }
            return error.UnknownOption;
        }

        return error.UnexpectedArgument;
    }

    if (since_millis != null and until_millis != null and since_millis.? > until_millis.?) {
        return error.InvalidDate;
    }

    return .{ .find = .{
        .tag = tag_name,
        .empty_filter = empty_filter,
        .since = since,
        .until = until,
        .since_millis = since_millis,
        .until_millis = until_millis,
        .limit = limit,
        .output = output,
        .fields = try fields.toOwnedSlice(),
    } };
}

// Parses `show <commitId>` plus output formatting and field selection options.
fn parseShow(allocator: std.mem.Allocator, args: []const []const u8) !types.ParsedRequest {
    var fields = std.array_list.Managed(types.ShowField).init(allocator);
    errdefer fields.deinit();

    var output: types.OutputFormat = .text;
    var commit_id: ?[]const u8 = null;
    var idx: usize = 0;
    var stop_option = false;
    while (idx < args.len) : (idx += 1) {
        const token = args[idx];

        if (!stop_option and scan.isDoubleDash(token)) {
            stop_option = true;
            continue;
        }

        if (!stop_option) {
            if (scan.parseLongOption(token)) |opt| {
                if (scan.equalsIgnoreAsciiCase(opt.key, "output")) {
                    const value = try scan.optionValue(args, &idx, opt.value);
                    output = try parseOutputFormat(value);
                    continue;
                }

                if (scan.equalsIgnoreAsciiCase(opt.key, "field")) {
                    const value = try scan.optionValue(args, &idx, opt.value);
                    try fields.append(try parseShowField(value));
                    continue;
                }
            }
        }

        if (commit_id != null) return error.UnexpectedArgument;
        commit_id = token;
    }

    return .{ .show = .{
        .commit_id = commit_id orelse return error.MissingArgument,
        .output = output,
        .fields = try fields.toOwnedSlice(),
    } };
}

// Parses supported output formats for reference-style commands.
fn parseOutputFormat(value: []const u8) !types.OutputFormat {
    if (scan.equalsIgnoreAsciiCase(value, "text")) return .text;
    if (scan.equalsIgnoreAsciiCase(value, "json")) return .json;
    return error.InvalidArgument;
}

// Parses a `tracklist` field name into its enum form.
fn parseTracklistField(value: []const u8) !types.TracklistField {
    if (scan.equalsIgnoreAsciiCase(value, "id")) return .id;
    if (scan.equalsIgnoreAsciiCase(value, "path")) return .path;
    return error.InvalidArgument;
}

// Parses a `find` field name into its enum form.
fn parseFindField(value: []const u8) !types.FindField {
    if (scan.equalsIgnoreAsciiCase(value, "commit_id")) return .commit_id;
    if (scan.equalsIgnoreAsciiCase(value, "message")) return .message;
    if (scan.equalsIgnoreAsciiCase(value, "created_at")) return .created_at;
    return error.InvalidArgument;
}

// Parses a `find` limit and enforces the supported 1..500 range.
fn parseFindLimit(value: []const u8) !usize {
    const parsed = std.fmt.parseInt(usize, value, 10) catch return error.InvalidArgument;
    if (parsed < 1 or parsed > 500) return error.InvalidArgument;
    return parsed;
}

// Parses a `show` field name into its enum form.
fn parseShowField(value: []const u8) !types.ShowField {
    if (scan.equalsIgnoreAsciiCase(value, "commit_id")) return .commit_id;
    if (scan.equalsIgnoreAsciiCase(value, "message")) return .message;
    if (scan.equalsIgnoreAsciiCase(value, "created_at")) return .created_at;
    if (scan.equalsIgnoreAsciiCase(value, "paths")) return .paths;
    if (scan.equalsIgnoreAsciiCase(value, "tags")) return .tags;
    return error.InvalidArgument;
}

test "parser preserves show unknown long option behavior" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{ "show", "--bogus" };
    var parsed = try parseArgs(allocator, &argv);
    defer types.deinitParsedRequest(allocator, &parsed);

    switch (parsed) {
        .show => |args| try std.testing.expectEqualStrings("--bogus", args.commit_id),
        else => return error.UnexpectedResult,
    }
}

test "parser resolves longest command match for tag subcommands" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{ "tag", "ls", "abc" };
    var parsed = try parseArgs(allocator, &argv);
    defer types.deinitParsedRequest(allocator, &parsed);

    switch (parsed) {
        .tag_ls => |args| try std.testing.expectEqualStrings("abc", args.commit_id),
        else => return error.UnexpectedResult,
    }
}

test "parser accepts bare tag command" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{"tag"};
    var parsed = try parseArgs(allocator, &argv);
    defer types.deinitParsedRequest(allocator, &parsed);

    switch (parsed) {
        .tag => {},
        else => return error.UnexpectedResult,
    }
}

test "parser accepts multiple positional paths for track add and rm" {
    const allocator = std.testing.allocator;

    {
        const argv = [_][]const u8{ "track", "./a.md", "./b.md" };
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);

        switch (parsed) {
            .track => |args| {
                try std.testing.expectEqual(@as(usize, 2), args.paths.len);
                try std.testing.expectEqualStrings("./a.md", args.paths[0]);
                try std.testing.expectEqualStrings("./b.md", args.paths[1]);
            },
            else => return error.UnexpectedResult,
        }
    }

    {
        const argv = [_][]const u8{ "add", "./a.md", "./b.md" };
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);

        switch (parsed) {
            .add => |args| {
                try std.testing.expect(!args.all);
                try std.testing.expectEqual(@as(usize, 2), args.paths.len);
                try std.testing.expectEqualStrings("./a.md", args.paths[0]);
                try std.testing.expectEqualStrings("./b.md", args.paths[1]);
            },
            else => return error.UnexpectedResult,
        }
    }

    {
        const argv = [_][]const u8{ "rm", "./a.md", "./b.md" };
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);

        switch (parsed) {
            .rm => |args| {
                try std.testing.expect(!args.all);
                try std.testing.expectEqual(@as(usize, 2), args.paths.len);
                try std.testing.expectEqualStrings("./a.md", args.paths[0]);
                try std.testing.expectEqualStrings("./b.md", args.paths[1]);
            },
            else => return error.UnexpectedResult,
        }
    }
}

test "parser accepts add all options" {
    const allocator = std.testing.allocator;

    {
        const argv = [_][]const u8{ "add", "-a" };
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);

        switch (parsed) {
            .add => |args| {
                try std.testing.expect(args.all);
                try std.testing.expectEqual(@as(usize, 0), args.paths.len);
            },
            else => return error.UnexpectedResult,
        }
    }

    {
        const argv = [_][]const u8{ "add", "--all" };
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);

        switch (parsed) {
            .add => |args| {
                try std.testing.expect(args.all);
                try std.testing.expectEqual(@as(usize, 0), args.paths.len);
            },
            else => return error.UnexpectedResult,
        }
    }

    {
        const argv = [_][]const u8{ "add", "--", "--all" };
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);

        switch (parsed) {
            .add => |args| {
                try std.testing.expect(!args.all);
                try std.testing.expectEqual(@as(usize, 1), args.paths.len);
                try std.testing.expectEqualStrings("--all", args.paths[0]);
            },
            else => return error.UnexpectedResult,
        }
    }
}

test "parser rejects add all mixed with paths" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(error.UnexpectedArgument, parseArgs(allocator, &.{ "add", "-a", "./a.md" }));
    try std.testing.expectError(error.UnexpectedArgument, parseArgs(allocator, &.{ "add", "--all", "./a.md" }));
    try std.testing.expectError(error.UnknownOption, parseArgs(allocator, &.{ "add", "--all=value" }));
}

test "parser accepts rm all options" {
    const allocator = std.testing.allocator;

    {
        const argv = [_][]const u8{ "rm", "-a" };
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);

        switch (parsed) {
            .rm => |args| {
                try std.testing.expect(args.all);
                try std.testing.expectEqual(@as(usize, 0), args.paths.len);
            },
            else => return error.UnexpectedResult,
        }
    }

    {
        const argv = [_][]const u8{ "rm", "--all" };
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);

        switch (parsed) {
            .rm => |args| {
                try std.testing.expect(args.all);
                try std.testing.expectEqual(@as(usize, 0), args.paths.len);
            },
            else => return error.UnexpectedResult,
        }
    }

    {
        const argv = [_][]const u8{ "rm", "--", "--all" };
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);

        switch (parsed) {
            .rm => |args| {
                try std.testing.expect(!args.all);
                try std.testing.expectEqual(@as(usize, 1), args.paths.len);
                try std.testing.expectEqualStrings("--all", args.paths[0]);
            },
            else => return error.UnexpectedResult,
        }
    }
}

test "parser rejects rm all mixed with paths" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(error.UnexpectedArgument, parseArgs(allocator, &.{ "rm", "-a", "./a.md" }));
    try std.testing.expectError(error.UnexpectedArgument, parseArgs(allocator, &.{ "rm", "--all", "./a.md" }));
    try std.testing.expectError(error.UnknownOption, parseArgs(allocator, &.{ "rm", "--all=value" }));
}

test "parser accepts untrack id and missing option" {
    const allocator = std.testing.allocator;

    {
        const argv = [_][]const u8{ "untrack", "abc" };
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);

        switch (parsed) {
            .untrack => |args| {
                try std.testing.expectEqualStrings("abc", args.tracked_file_id.?);
                try std.testing.expect(!args.missing);
            },
            else => return error.UnexpectedResult,
        }
    }

    {
        const argv = [_][]const u8{ "untrack", "--missing" };
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);

        switch (parsed) {
            .untrack => |args| {
                try std.testing.expect(args.tracked_file_id == null);
                try std.testing.expect(args.missing);
            },
            else => return error.UnexpectedResult,
        }
    }
}

test "parser rejects mixed or invalid untrack missing usage" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(error.UnexpectedArgument, parseArgs(allocator, &.{ "untrack", "--missing", "abc" }));
    try std.testing.expectError(error.UnexpectedArgument, parseArgs(allocator, &.{ "untrack", "abc", "--missing" }));
    try std.testing.expectError(error.UnknownOption, parseArgs(allocator, &.{ "untrack", "--missing=yes" }));
}

test "parser accepts commit options" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{ "commit", "-e", "-m", "msg", "--tag=release", "-t", "prod", "--dry-run" };
    var parsed = try parseArgs(allocator, &argv);
    defer types.deinitParsedRequest(allocator, &parsed);

    switch (parsed) {
        .commit => |args| {
            try std.testing.expectEqualStrings("msg", args.message);
            try std.testing.expect(args.dry_run);
            try std.testing.expect(args.empty);
            try std.testing.expectEqual(@as(usize, 2), args.tags.len);
            try std.testing.expectEqualStrings("release", args.tags[0]);
            try std.testing.expectEqualStrings("prod", args.tags[1]);
        },
        else => return error.UnexpectedResult,
    }
}

test "parser accepts commit long message option" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{ "commit", "--message", "msg" };
    var parsed = try parseArgs(allocator, &argv);
    defer types.deinitParsedRequest(allocator, &parsed);

    switch (parsed) {
        .commit => |args| {
            try std.testing.expectEqualStrings("msg", args.message);
            try std.testing.expect(!args.dry_run);
            try std.testing.expect(!args.empty);
            try std.testing.expectEqual(@as(usize, 0), args.tags.len);
        },
        else => return error.UnexpectedResult,
    }
}

test "parser accepts commit empty long option" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{ "commit", "--empty", "--message", "msg" };
    var parsed = try parseArgs(allocator, &argv);
    defer types.deinitParsedRequest(allocator, &parsed);

    switch (parsed) {
        .commit => |args| {
            try std.testing.expectEqualStrings("msg", args.message);
            try std.testing.expect(args.empty);
            try std.testing.expect(!args.dry_run);
            try std.testing.expectEqual(@as(usize, 0), args.tags.len);
        },
        else => return error.UnexpectedResult,
    }
}

test "parser rejects commit empty option with value" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.UnknownOption, parseArgs(allocator, &.{ "commit", "--empty=yes", "-m", "msg" }));
}

test "parser resolves help from help aliases and accepts topic" {
    const allocator = std.testing.allocator;

    {
        const argv = [_][]const u8{};
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);
        switch (parsed) {
            .help => |args| try std.testing.expect(args.topic == null),
            else => return error.UnexpectedResult,
        }
    }

    {
        const argv = [_][]const u8{"-h"};
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);
        switch (parsed) {
            .help => |args| try std.testing.expect(args.topic == null),
            else => return error.UnexpectedResult,
        }
    }

    {
        const argv = [_][]const u8{"--HELP"};
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);
        switch (parsed) {
            .help => |args| try std.testing.expect(args.topic == null),
            else => return error.UnexpectedResult,
        }
    }

    {
        const argv = [_][]const u8{ "help", "commit" };
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);
        switch (parsed) {
            .help => |args| try std.testing.expectEqualStrings("commit", args.topic.?),
            else => return error.UnexpectedResult,
        }
    }
}

test "parser accepts journal with no args" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{"journal"};
    var parsed = try parseArgs(allocator, &argv);
    defer types.deinitParsedRequest(allocator, &parsed);

    switch (parsed) {
        .journal => {},
        else => return error.UnexpectedResult,
    }
}

test "parser rejects extra positional for journal" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{ "journal", "extra" };
    try std.testing.expectError(error.UnexpectedArgument, parseArgs(allocator, &argv));
}

test "parser rejects help with too many topics" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{ "help", "commit", "extra" };
    try std.testing.expectError(error.UnexpectedArgument, parseArgs(allocator, &argv));
}

test "parser accepts internal complete command with index and words" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{ "__complete", "--index", "2", "--", "omohi", "show", "" };
    var parsed = try parseArgs(allocator, &argv);
    defer types.deinitParsedRequest(allocator, &parsed);

    switch (parsed) {
        .complete => |args| {
            try std.testing.expectEqual(@as(usize, 2), args.index);
            try std.testing.expectEqual(@as(usize, 3), args.words.len);
            try std.testing.expectEqualStrings("omohi", args.words[0]);
            try std.testing.expectEqualStrings("show", args.words[1]);
            try std.testing.expectEqualStrings("", args.words[2]);
        },
        else => return error.UnexpectedResult,
    }
}

test "parser rejects internal complete command when index is outside words" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{ "__complete", "--index=3", "--", "omohi", "show", "" };
    try std.testing.expectError(error.InvalidArgument, parseArgs(allocator, &argv));
}

test "parser resolves version from command and aliases" {
    const allocator = std.testing.allocator;

    {
        const argv = [_][]const u8{"version"};
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);
        switch (parsed) {
            .version => {},
            else => return error.UnexpectedResult,
        }
    }

    {
        const argv = [_][]const u8{"-v"};
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);
        switch (parsed) {
            .version => {},
            else => return error.UnexpectedResult,
        }
    }

    {
        const argv = [_][]const u8{"--version"};
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);
        switch (parsed) {
            .version => {},
            else => return error.UnexpectedResult,
        }
    }
}

test "parser rejects extra arguments for version" {
    const allocator = std.testing.allocator;

    {
        const argv = [_][]const u8{ "version", "extra" };
        try std.testing.expectError(error.UnexpectedArgument, parseArgs(allocator, &argv));
    }
    {
        const argv = [_][]const u8{ "-v", "extra" };
        try std.testing.expectError(error.UnexpectedArgument, parseArgs(allocator, &argv));
    }
    {
        const argv = [_][]const u8{ "--version", "extra" };
        try std.testing.expectError(error.UnexpectedArgument, parseArgs(allocator, &argv));
    }
}

test "parser normalizes option keys for commit" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{ "commit", "-M", "msg", "--TAG=release", "--DRY-RUN" };
    var parsed = try parseArgs(allocator, &argv);
    defer types.deinitParsedRequest(allocator, &parsed);

    switch (parsed) {
        .commit => |args| {
            try std.testing.expectEqualStrings("msg", args.message);
            try std.testing.expect(args.dry_run);
            try std.testing.expectEqual(@as(usize, 1), args.tags.len);
            try std.testing.expectEqualStrings("release", args.tags[0]);
        },
        else => return error.UnexpectedResult,
    }
}

test "parser normalizes option keys for find" {
    const allocator = std.testing.allocator;

    {
        const argv = [_][]const u8{ "find", "--TAG", "release", "--SINCE=2026-03-12", "--UNTIL", "2026-03-13" };
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);
        switch (parsed) {
            .find => |args| {
                try std.testing.expectEqualStrings("release", args.tag.?);
                try std.testing.expectEqual(types.FindEmptyFilter.all, args.empty_filter);
                try std.testing.expectEqualStrings("2026-03-12", args.since.?);
                try std.testing.expectEqualStrings("2026-03-13", args.until.?);
            },
            else => return error.UnexpectedResult,
        }
    }

    {
        const argv = [_][]const u8{ "find", "-T", "release", "-S", "2026-03-12", "-U", "2026-03-13T12:00:00" };
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);
        switch (parsed) {
            .find => |args| {
                try std.testing.expectEqualStrings("release", args.tag.?);
                try std.testing.expectEqual(types.FindEmptyFilter.all, args.empty_filter);
                try std.testing.expectEqualStrings("2026-03-12", args.since.?);
                try std.testing.expectEqualStrings("2026-03-13T12:00:00", args.until.?);
            },
            else => return error.UnexpectedResult,
        }
    }
}

test "parser rejects invalid find date format" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidDate, parseArgs(allocator, &.{ "find", "--since", "2026/03/12" }));
    try std.testing.expectError(error.InvalidDate, parseArgs(allocator, &.{ "find", "--until", "2026-03-12T00:00:00Z" }));
}

test "parser rejects reversed find time range" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidDate, parseArgs(allocator, &.{ "find", "--since", "2026-03-13", "--until", "2026-03-12" }));
}

test "parser accepts tracklist output and repeated fields" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{ "tracklist", "--output", "json", "--field=id", "--field", "path" };
    var parsed = try parseArgs(allocator, &argv);
    defer types.deinitParsedRequest(allocator, &parsed);

    switch (parsed) {
        .tracklist => |args| {
            try std.testing.expectEqual(types.OutputFormat.json, args.output);
            try std.testing.expectEqual(@as(usize, 2), args.fields.len);
            try std.testing.expectEqual(types.TracklistField.id, args.fields[0]);
            try std.testing.expectEqual(types.TracklistField.path, args.fields[1]);
        },
        else => return error.UnexpectedResult,
    }
}

test "parser accepts find output and repeated fields" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{ "find", "--output", "json", "--field", "commit_id", "--field=created_at" };
    var parsed = try parseArgs(allocator, &argv);
    defer types.deinitParsedRequest(allocator, &parsed);

    switch (parsed) {
        .find => |args| {
            try std.testing.expectEqual(types.OutputFormat.json, args.output);
            try std.testing.expectEqual(types.FindEmptyFilter.all, args.empty_filter);
            try std.testing.expectEqual(@as(usize, 2), args.fields.len);
            try std.testing.expectEqual(types.FindField.commit_id, args.fields[0]);
            try std.testing.expectEqual(types.FindField.created_at, args.fields[1]);
        },
        else => return error.UnexpectedResult,
    }
}

test "parser accepts find limit values" {
    const allocator = std.testing.allocator;

    {
        const argv = [_][]const u8{ "find", "--limit", "25" };
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);

        switch (parsed) {
            .find => |args| {
                try std.testing.expectEqual(types.FindEmptyFilter.all, args.empty_filter);
                try std.testing.expectEqual(@as(?usize, 25), args.limit);
            },
            else => return error.UnexpectedResult,
        }
    }

    {
        const argv = [_][]const u8{ "find", "--limit=500" };
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);

        switch (parsed) {
            .find => |args| {
                try std.testing.expectEqual(types.FindEmptyFilter.all, args.empty_filter);
                try std.testing.expectEqual(@as(?usize, 500), args.limit);
            },
            else => return error.UnexpectedResult,
        }
    }
}

test "parser accepts find empty filters" {
    const allocator = std.testing.allocator;

    {
        var parsed = try parseArgs(allocator, &.{ "find", "--empty" });
        defer types.deinitParsedRequest(allocator, &parsed);

        switch (parsed) {
            .find => |args| try std.testing.expectEqual(types.FindEmptyFilter.empty_only, args.empty_filter),
            else => return error.UnexpectedResult,
        }
    }

    {
        var parsed = try parseArgs(allocator, &.{ "find", "--no-empty" });
        defer types.deinitParsedRequest(allocator, &parsed);

        switch (parsed) {
            .find => |args| try std.testing.expectEqual(types.FindEmptyFilter.non_empty_only, args.empty_filter),
            else => return error.UnexpectedResult,
        }
    }
}

test "parser rejects invalid find limit values" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.MissingValue, parseArgs(allocator, &.{ "find", "--limit" }));
    try std.testing.expectError(error.InvalidArgument, parseArgs(allocator, &.{ "find", "--limit", "0" }));
    try std.testing.expectError(error.InvalidArgument, parseArgs(allocator, &.{ "find", "--limit", "501" }));
    try std.testing.expectError(error.InvalidArgument, parseArgs(allocator, &.{ "find", "--limit", "abc" }));
}

test "parser rejects conflicting find empty filters" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidArgument, parseArgs(allocator, &.{ "find", "--empty", "--no-empty" }));
    try std.testing.expectError(error.InvalidArgument, parseArgs(allocator, &.{ "find", "--no-empty", "--empty" }));
}

test "parser rejects find empty filters with values" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.UnknownOption, parseArgs(allocator, &.{ "find", "--empty=true" }));
    try std.testing.expectError(error.UnknownOption, parseArgs(allocator, &.{ "find", "--no-empty=false" }));
}

test "parser accepts show options before commit id" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{ "show", "--field", "commit_id", "--output=text", "abc" };
    var parsed = try parseArgs(allocator, &argv);
    defer types.deinitParsedRequest(allocator, &parsed);

    switch (parsed) {
        .show => |args| {
            try std.testing.expectEqualStrings("abc", args.commit_id);
            try std.testing.expectEqual(types.OutputFormat.text, args.output);
            try std.testing.expectEqual(@as(usize, 1), args.fields.len);
            try std.testing.expectEqual(types.ShowField.commit_id, args.fields[0]);
        },
        else => return error.UnexpectedResult,
    }
}

test "parser rejects unknown reference fields" {
    const allocator = std.testing.allocator;

    {
        const argv = [_][]const u8{ "tracklist", "--field", "unknown" };
        try std.testing.expectError(error.InvalidArgument, parseArgs(allocator, &argv));
    }
    {
        const argv = [_][]const u8{ "find", "--field", "unknown" };
        try std.testing.expectError(error.InvalidArgument, parseArgs(allocator, &argv));
    }
    {
        const argv = [_][]const u8{ "show", "--field", "unknown", "abc" };
        try std.testing.expectError(error.InvalidArgument, parseArgs(allocator, &argv));
    }
}

test "parser keeps double-dash behavior for positional arguments" {
    const allocator = std.testing.allocator;
    const commit_argv = [_][]const u8{ "commit", "-m", "msg", "--", "--tag", "release" };
    try std.testing.expectError(error.UnexpectedArgument, parseArgs(allocator, &commit_argv));

    const find_argv = [_][]const u8{ "find", "--", "--tag", "release" };
    try std.testing.expectError(error.UnexpectedArgument, parseArgs(allocator, &find_argv));
}
