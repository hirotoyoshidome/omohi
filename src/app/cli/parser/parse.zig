const std = @import("std");
const types = @import("types.zig");
const date_validation = @import("../validation/date.zig");

pub fn parseArgs(allocator: std.mem.Allocator, argv: []const []const u8) !types.ParsedRequest {
    if (argv.len == 0) return .help;

    if (std.mem.eql(u8, argv[0], "help")) {
        if (argv.len != 1) return error.UnexpectedArgument;
        return .help;
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
    if (std.mem.eql(u8, argv[0], "find")) return try parseFind(argv[1..]);
    if (std.mem.eql(u8, argv[0], "show")) return try parseShow(argv[1..]);

    return error.InvalidCommand;
}

fn parseNoArgsCommand(comptime tag: anytype, args: []const []const u8) !types.ParsedRequest {
    if (args.len != 0) return error.UnexpectedArgument;
    return @unionInit(types.ParsedRequest, @tagName(tag), {});
}

fn parseTrack(args: []const []const u8) !types.ParsedRequest {
    if (args.len != 1) return error.MissingArgument;
    return .{ .track = .{ .path = args[0] } };
}

fn parseUntrack(args: []const []const u8) !types.ParsedRequest {
    if (args.len != 1) return error.MissingArgument;
    return .{ .untrack = .{ .tracked_file_id = args[0] } };
}

fn parseAdd(args: []const []const u8) !types.ParsedRequest {
    if (args.len != 1) return error.MissingArgument;
    return .{ .add = .{ .path = args[0] } };
}

fn parseRm(args: []const []const u8) !types.ParsedRequest {
    if (args.len != 1) return error.MissingArgument;
    return .{ .rm = .{ .path = args[0] } };
}

fn parseShow(args: []const []const u8) !types.ParsedRequest {
    if (args.len != 1) return error.MissingArgument;
    return .{ .show = .{ .commit_id = args[0] } };
}

fn parseTagLs(args: []const []const u8) !types.ParsedRequest {
    if (args.len != 1) return error.MissingArgument;
    return .{ .tag_ls = .{ .commit_id = args[0] } };
}

fn parseTagAdd(args: []const []const u8) !types.ParsedRequest {
    if (args.len < 2) return error.MissingArgument;
    return .{ .tag_add = .{
        .commit_id = args[0],
        .tag_names = args[1..],
    } };
}

fn parseTagRm(args: []const []const u8) !types.ParsedRequest {
    if (args.len < 2) return error.MissingArgument;
    return .{ .tag_rm = .{
        .commit_id = args[0],
        .tag_names = args[1..],
    } };
}

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

        if (!stop_option and std.mem.startsWith(u8, token, "--")) {
            if (std.mem.eql(u8, token, "--dry-run")) {
                dry_run = true;
                continue;
            }

            if (std.mem.eql(u8, token, "--message")) {
                idx += 1;
                if (idx >= args.len) return error.MissingValue;
                message = args[idx];
                continue;
            }

            if (std.mem.startsWith(u8, token, "--message=")) {
                message = token["--message=".len..];
                continue;
            }

            if (std.mem.eql(u8, token, "--tag")) {
                idx += 1;
                if (idx >= args.len) return error.MissingValue;
                try tags.append(args[idx]);
                continue;
            }

            if (std.mem.startsWith(u8, token, "--tag=")) {
                try tags.append(token["--tag=".len..]);
                continue;
            }

            return error.UnknownOption;
        }

        if (!stop_option and std.mem.startsWith(u8, token, "-") and token.len > 1) {
            if (std.mem.eql(u8, token, "-m")) {
                idx += 1;
                if (idx >= args.len) return error.MissingValue;
                message = args[idx];
                continue;
            }

            if (std.mem.eql(u8, token, "-t")) {
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

        if (!stop_option and std.mem.startsWith(u8, token, "--")) {
            if (std.mem.eql(u8, token, "--tag")) {
                idx += 1;
                if (idx >= args.len) return error.MissingValue;
                tag_name = args[idx];
                continue;
            }

            if (std.mem.startsWith(u8, token, "--tag=")) {
                tag_name = token["--tag=".len..];
                continue;
            }

            if (std.mem.eql(u8, token, "--date")) {
                idx += 1;
                if (idx >= args.len) return error.MissingValue;
                try date_validation.validateDateYmd(args[idx]);
                date = args[idx];
                continue;
            }

            if (std.mem.startsWith(u8, token, "--date=")) {
                const raw = token["--date=".len..];
                try date_validation.validateDateYmd(raw);
                date = raw;
                continue;
            }

            return error.UnknownOption;
        }

        if (!stop_option and std.mem.startsWith(u8, token, "-") and token.len > 1) {
            if (std.mem.eql(u8, token, "-t")) {
                idx += 1;
                if (idx >= args.len) return error.MissingValue;
                tag_name = args[idx];
                continue;
            }
            if (std.mem.eql(u8, token, "-d")) {
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
