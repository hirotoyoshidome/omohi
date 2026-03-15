const std = @import("std");
const parser_types = @import("../parser/types.zig");

pub const PreparedJournalEvent = struct {
    command_type: []const u8,
    payload_json: []u8,

    pub fn deinit(self: *PreparedJournalEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.payload_json);
    }
};

pub fn fromParsedRequest(
    allocator: std.mem.Allocator,
    parsed: parser_types.ParsedRequest,
) !?PreparedJournalEvent {
    return switch (parsed) {
        .track => |args| try makeEvent(allocator, "track", .{ .path = args.path }),
        .untrack => |args| try makeEvent(allocator, "untrack", .{ .trackedFileId = args.tracked_file_id }),
        .add => |args| try makeEvent(allocator, "add", .{ .path = args.path }),
        .rm => |args| try makeEvent(allocator, "rm", .{ .path = args.path }),
        .commit => |args| blk: {
            if (args.dry_run) break :blk null;
            break :blk try makeEvent(allocator, "commit", .{
                .message = args.message,
                .tags = args.tags,
                .dryRun = false,
            });
        },
        .tag_add => |args| try makeEvent(allocator, "tag-add", .{
            .commitId = args.commit_id,
            .tagNames = args.tag_names,
        }),
        .tag_rm => |args| try makeEvent(allocator, "tag-rm", .{
            .commitId = args.commit_id,
            .tagNames = args.tag_names,
        }),
        else => null,
    };
}

fn makeEvent(
    allocator: std.mem.Allocator,
    command_type: []const u8,
    payload: anytype,
) !PreparedJournalEvent {
    const payload_json = try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(payload, .{})});
    return .{
        .command_type = command_type,
        .payload_json = payload_json,
    };
}

test "fromParsedRequest maps mutating command to event" {
    const parsed: parser_types.ParsedRequest = .{ .add = .{ .path = "/tmp/a b.txt" } };
    var event = (try fromParsedRequest(std.testing.allocator, parsed)).?;
    defer event.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("add", event.command_type);
    try std.testing.expect(std.mem.indexOf(u8, event.payload_json, "\"path\":\"/tmp/a b.txt\"") != null);
}

test "fromParsedRequest skips commit dry-run" {
    const tags = [_][]const u8{"release"};
    const parsed: parser_types.ParsedRequest = .{ .commit = .{
        .message = "m",
        .tags = &tags,
        .dry_run = true,
    } };

    const maybe_event = try fromParsedRequest(std.testing.allocator, parsed);
    try std.testing.expect(maybe_event == null);
}
