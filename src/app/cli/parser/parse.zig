const std = @import("std");
const types = @import("types.zig");
const date_validation = @import("../validation/date.zig");

// Parses CLI argv tokens into a typed request; commit requests may allocate owned tag slices.
pub fn parseArgs(allocator: std.mem.Allocator, argv: []const []const u8) !types.ParsedRequest {
    if (argv.len == 0) return .{ .help = .{ .topic = null } };

    if (equalsIgnoreAsciiCase(argv[0], "-h") or equalsIgnoreAsciiCase(argv[0], "--help")) {
        return try parseHelp(argv[1..]);
    }

    if (equalsIgnoreAsciiCase(argv[0], "-v") or equalsIgnoreAsciiCase(argv[0], "--version")) {
        return try parseNoArgsCommand(.version, argv[1..]);
    }

    if (equalsIgnoreAsciiCase(argv[0], "help")) {
        return try parseHelp(argv[1..]);
    }

    if (std.mem.eql(u8, argv[0], "__complete")) {
        return try parseComplete(argv[1..]);
    }

    if (argv.len >= 2 and std.mem.eql(u8, argv[0], "tag")) {
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
    if (std.mem.eql(u8, argv[0], "tracklist")) return try parseNoArgsCommand(.tracklist, argv[1..]);
    if (std.mem.eql(u8, argv[0], "version")) return try parseNoArgsCommand(.version, argv[1..]);
    if (std.mem.eql(u8, argv[0], "find")) return try parseFind(argv[1..]);
    if (std.mem.eql(u8, argv[0], "show")) return try parseShow(argv[1..]);
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

        if (!stop_option and std.mem.eql(u8, token, "--")) {
            stop_option = true;
            idx += 1;
            break;
        }

        if (!stop_option) {
            if (parseLongOption(token)) |opt| {
                if (equalsIgnoreAsciiCase(opt.key, "index")) {
                    const value = opt.value orelse blk: {
                        idx += 1;
                        if (idx >= args.len) return error.MissingValue;
                        break :blk args[idx];
                    };
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

// Compares tokens case-insensitively for CLI aliases and option keys.
fn equalsIgnoreAsciiCase(lhs: []const u8, rhs: []const u8) bool {
    return std.ascii.eqlIgnoreCase(lhs, rhs);
}

// Parses a `--key` or `--key=value` token and returns null for non-long options.
fn parseLongOption(token: []const u8) ?struct { key: []const u8, value: ?[]const u8 } {
    if (!std.mem.startsWith(u8, token, "--")) return null;
    const body = token[2..];
    if (body.len == 0) return null;

    if (std.mem.indexOfScalar(u8, body, '=')) |eq| {
        const key = body[0..eq];
        const value = body[eq + 1 ..];
        if (key.len == 0) return null;
        return .{ .key = key, .value = value };
    }

    return .{ .key = body, .value = null };
}

// Parses `track <path>`.
fn parseTrack(args: []const []const u8) !types.ParsedRequest {
    if (args.len != 1) return error.MissingArgument;
    return .{ .track = .{ .path = args[0] } };
}

// Parses `untrack <trackedFileId>`.
fn parseUntrack(args: []const []const u8) !types.ParsedRequest {
    if (args.len != 1) return error.MissingArgument;
    return .{ .untrack = .{ .tracked_file_id = args[0] } };
}

// Parses `add <path>`.
fn parseAdd(args: []const []const u8) !types.ParsedRequest {
    if (args.len != 1) return error.MissingArgument;
    return .{ .add = .{ .path = args[0] } };
}

// Parses `rm <path>`.
fn parseRm(args: []const []const u8) !types.ParsedRequest {
    if (args.len != 1) return error.MissingArgument;
    return .{ .rm = .{ .path = args[0] } };
}

// Parses `show <commitId>`.
fn parseShow(args: []const []const u8) !types.ParsedRequest {
    if (args.len != 1) return error.MissingArgument;
    return .{ .show = .{ .commit_id = args[0] } };
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
    var tags = std.array_list.Managed([]const u8).init(allocator);
    errdefer tags.deinit();

    var idx: usize = 0;
    var stop_option = false;
    while (idx < args.len) : (idx += 1) {
        const token = args[idx];

        if (!stop_option and std.mem.eql(u8, token, "--")) {
            stop_option = true;
            continue;
        }

        if (!stop_option) {
            if (parseLongOption(token)) |opt| {
                if (equalsIgnoreAsciiCase(opt.key, "dry-run")) {
                    if (opt.value != null) return error.UnknownOption;
                    dry_run = true;
                    continue;
                }

                if (equalsIgnoreAsciiCase(opt.key, "message")) {
                    if (opt.value) |value| {
                        message = value;
                        continue;
                    }
                    idx += 1;
                    if (idx >= args.len) return error.MissingValue;
                    message = args[idx];
                    continue;
                }

                if (equalsIgnoreAsciiCase(opt.key, "tag")) {
                    if (opt.value) |value| {
                        try tags.append(value);
                        continue;
                    }
                    idx += 1;
                    if (idx >= args.len) return error.MissingValue;
                    try tags.append(args[idx]);
                    continue;
                }

                return error.UnknownOption;
            }
        }

        if (!stop_option and std.mem.startsWith(u8, token, "-") and token.len > 1) {
            if (equalsIgnoreAsciiCase(token, "-m")) {
                idx += 1;
                if (idx >= args.len) return error.MissingValue;
                message = args[idx];
                continue;
            }

            if (equalsIgnoreAsciiCase(token, "-t")) {
                idx += 1;
                if (idx >= args.len) return error.MissingValue;
                try tags.append(args[idx]);
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
    } };
}

// Parses `find` options and validates any provided date filter.
fn parseFind(args: []const []const u8) !types.ParsedRequest {
    var tag_name: ?[]const u8 = null;
    var date: ?[]const u8 = null;

    var idx: usize = 0;
    var stop_option = false;
    while (idx < args.len) : (idx += 1) {
        const token = args[idx];

        if (!stop_option and std.mem.eql(u8, token, "--")) {
            stop_option = true;
            continue;
        }

        if (!stop_option) {
            if (parseLongOption(token)) |opt| {
                if (equalsIgnoreAsciiCase(opt.key, "tag")) {
                    if (opt.value) |value| {
                        tag_name = value;
                        continue;
                    }
                    idx += 1;
                    if (idx >= args.len) return error.MissingValue;
                    tag_name = args[idx];
                    continue;
                }

                if (equalsIgnoreAsciiCase(opt.key, "date")) {
                    if (opt.value) |value| {
                        try date_validation.validateDateYmd(value);
                        date = value;
                        continue;
                    }
                    idx += 1;
                    if (idx >= args.len) return error.MissingValue;
                    try date_validation.validateDateYmd(args[idx]);
                    date = args[idx];
                    continue;
                }

                return error.UnknownOption;
            }
        }

        if (!stop_option and std.mem.startsWith(u8, token, "-") and token.len > 1) {
            if (equalsIgnoreAsciiCase(token, "-t")) {
                idx += 1;
                if (idx >= args.len) return error.MissingValue;
                tag_name = args[idx];
                continue;
            }
            if (equalsIgnoreAsciiCase(token, "-d")) {
                idx += 1;
                if (idx >= args.len) return error.MissingValue;
                try date_validation.validateDateYmd(args[idx]);
                date = args[idx];
                continue;
            }
            return error.UnknownOption;
        }

        return error.UnexpectedArgument;
    }

    return .{ .find = .{
        .tag = tag_name,
        .date = date,
    } };
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

test "parser accepts commit options" {
    const allocator = std.testing.allocator;
    const argv = [_][]const u8{ "commit", "-m", "msg", "--tag=release", "-t", "prod", "--dry-run" };
    var parsed = try parseArgs(allocator, &argv);
    defer types.deinitParsedRequest(allocator, &parsed);

    switch (parsed) {
        .commit => |args| {
            try std.testing.expectEqualStrings("msg", args.message);
            try std.testing.expect(args.dry_run);
            try std.testing.expectEqual(@as(usize, 2), args.tags.len);
            try std.testing.expectEqualStrings("release", args.tags[0]);
            try std.testing.expectEqualStrings("prod", args.tags[1]);
        },
        else => return error.UnexpectedResult,
    }
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
        const argv = [_][]const u8{ "find", "--TAG", "release", "--DATE=2026-03-12" };
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);
        switch (parsed) {
            .find => |args| {
                try std.testing.expectEqualStrings("release", args.tag.?);
                try std.testing.expectEqualStrings("2026-03-12", args.date.?);
            },
            else => return error.UnexpectedResult,
        }
    }

    {
        const argv = [_][]const u8{ "find", "-T", "release", "-D", "2026-03-12" };
        var parsed = try parseArgs(allocator, &argv);
        defer types.deinitParsedRequest(allocator, &parsed);
        switch (parsed) {
            .find => |args| {
                try std.testing.expectEqualStrings("release", args.tag.?);
                try std.testing.expectEqualStrings("2026-03-12", args.date.?);
            },
            else => return error.UnexpectedResult,
        }
    }
}

test "parser keeps double-dash behavior for positional arguments" {
    const allocator = std.testing.allocator;
    const commit_argv = [_][]const u8{ "commit", "-m", "msg", "--", "--tag", "release" };
    try std.testing.expectError(error.UnexpectedArgument, parseArgs(allocator, &commit_argv));

    const find_argv = [_][]const u8{ "find", "--", "--tag", "release" };
    try std.testing.expectError(error.UnexpectedArgument, parseArgs(allocator, &find_argv));
}
