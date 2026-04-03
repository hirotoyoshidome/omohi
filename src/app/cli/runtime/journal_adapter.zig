const std = @import("std");
const parser_types = @import("../parser/types.zig");

pub const PreparedJournalEvent = struct {
    command_type: []const u8,
    payload_json: []u8,

    // Releases the owned JSON payload buffer for the prepared journal event.
    pub fn deinit(self: *PreparedJournalEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.payload_json);
    }
};

// Converts mutating parsed requests into owned journal events and skips non-persisted commands.
pub fn fromParsedRequest(
    allocator: std.mem.Allocator,
    parsed: parser_types.ParsedRequest,
) !?PreparedJournalEvent {
    return switch (parsed) {
        .track => |args| try makeEvent(allocator, "track", .{ .paths = args.paths }),
        .untrack => |args| try makeEvent(allocator, "untrack", .{ .trackedFileId = args.tracked_file_id }),
        .add => |args| try makeEvent(allocator, "add", .{ .paths = args.paths }),
        .rm => |args| try makeEvent(allocator, "rm", .{ .paths = args.paths }),
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
        .journal => null,
        .complete => null,
        else => null,
    };
}

// Formats a journal event payload as owned JSON for later persistence.
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
    const paths = [_][]const u8{ "/tmp/a b.txt", "/tmp/c.txt" };
    const parsed: parser_types.ParsedRequest = .{ .add = .{ .paths = &paths } };
    var event = (try fromParsedRequest(std.testing.allocator, parsed)).?;
    defer event.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("add", event.command_type);
    try std.testing.expect(std.mem.indexOf(u8, event.payload_json, "\"paths\":[\"/tmp/a b.txt\",\"/tmp/c.txt\"]") != null);
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
