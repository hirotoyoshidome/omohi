const std = @import("std");

const ContentEntry = @import("../object/content_entry.zig").ContentEntry;
const PersistenceLayout = @import("../object/persistence_layout.zig").PersistenceLayout;
const atomic_write = @import("../storage/atomic_write.zig");
const constrained_types = @import("../object/constrained_types.zig");

pub fn writeSnapshot(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    snapshot_id: []const u8,
    entries: []const ContentEntry,
) !void {
    const content = try formatSnapshotEntries(allocator, entries);
    defer allocator.free(content);

    const path = try persistence.snapshotsPath(allocator, snapshot_id);
    defer allocator.free(path);

    try atomic_write.atomicWrite(allocator, persistence.dir, path, content);
}

fn formatSnapshotEntries(allocator: std.mem.Allocator, entries: []const ContentEntry) ![]u8 {
    var buffer = std.array_list.Managed(u8).init(allocator);
    defer buffer.deinit();

    var writer = buffer.writer();
    try writer.writeAll("entries=");
    for (entries, 0..) |entry, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.print("{s}:{s}", .{ entry.path.asSlice(), entry.content_hash.asSlice() });
    }
    try writer.writeByte('\n');

    return buffer.toOwnedSlice();
}

test "writeSnapshot persists entries with predictable format" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    var persistence = PersistenceLayout.init(omohi_dir);
    var snapshot_id: [64]u8 = undefined;
    @memset(&snapshot_id, 'c');

    var entries = [_]ContentEntry{
        .{
            .path = try constrained_types.TrackedFilePath.init(try allocator.dupe(u8, "/tmp/file-a.txt")),
            .content_hash = try constrained_types.ContentHash.init(blk: {
                var buf: [64]u8 = undefined;
                @memset(&buf, '1');
                break :blk &buf;
            }),
        },
        .{
            .path = try constrained_types.TrackedFilePath.init(try allocator.dupe(u8, "/tmp/file-b.txt")),
            .content_hash = try constrained_types.ContentHash.init(blk: {
                var buf: [64]u8 = undefined;
                @memset(&buf, '2');
                break :blk &buf;
            }),
        },
    };
    defer allocator.free(@constCast(entries[0].path.asSlice()));
    defer allocator.free(@constCast(entries[1].path.asSlice()));

    try writeSnapshot(allocator, persistence, &snapshot_id, &entries);

    const path = try persistence.snapshotsPath(allocator, &snapshot_id);
    defer allocator.free(path);

    const content = try omohi_dir.readFileAlloc(allocator, path, 4096);
    defer allocator.free(content);

    try std.testing.expectEqualStrings(
        "entries=/tmp/file-a.txt:1111111111111111111111111111111111111111111111111111111111111111,/tmp/file-b.txt:2222222222222222222222222222222222222222222222222222222222222222\n",
        content,
    );
}
