const std = @import("std");

const atomic_write = @import("../atomic_write.zig");
const trash = @import("./trash.zig");
const PersistenceLayout = @import("../../object/persistence_layout.zig").PersistenceLayout;
const constrained_types = @import("../../object/constrained_types.zig");

pub const TrackedEntry = struct {
    id: constrained_types.TrackedFileId,
    path: constrained_types.TrackedFilePath,
};

pub const TrackedList = std.array_list.Managed(TrackedEntry);

const max_tracked_file_size = 16 * 1024;

pub fn writeTracked(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    tracked_file_id: []const u8,
    tracked_path: []const u8,
) !void {
    _ = try constrained_types.TrackedFileId.init(tracked_file_id);
    _ = try constrained_types.TrackedFilePath.init(tracked_path);

    const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.trackedPath(), tracked_file_id });
    defer allocator.free(path);

    try atomic_write.atomicWrite(allocator, persistence.dir, path, tracked_path);
}

pub fn deleteTracked(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    tracked_file_id: []const u8,
) !void {
    try trash.moveTrackedToTrash(allocator, persistence, tracked_file_id);
}

pub fn loadTracked(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
) !TrackedList {
    var dir = persistence.dir.openDir(persistence.trackedPath(), .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return error.MissingTracked,
        else => return err,
    };
    defer dir.close();

    var list = TrackedList.init(allocator);
    errdefer freeTrackedList(allocator, &list);

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;

        const id = try constrained_types.TrackedFileId.init(entry.name);
        const bytes = try dir.readFileAlloc(allocator, entry.name, max_tracked_file_size);
        defer allocator.free(bytes);

        const trimmed = std.mem.trim(u8, std.mem.trimRight(u8, bytes, "\r\n"), " \t");
        const path_copy = try allocator.dupe(u8, trimmed);
        errdefer allocator.free(path_copy);
        const tracked_path = try constrained_types.TrackedFilePath.init(path_copy);

        try list.append(.{
            .id = id,
            .path = tracked_path,
        });
    }

    return list;
}

pub fn freeTrackedList(allocator: std.mem.Allocator, list: *TrackedList) void {
    for (list.items) |entry| allocator.free(@constCast(entry.path.asSlice()));
    list.deinit();
}

test "writeTracked and loadTracked round-trip entries" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    const persistence = PersistenceLayout.init(omohi_dir);

    var tracked_id: [32]u8 = undefined;
    @memset(&tracked_id, 'b');
    try writeTracked(allocator, persistence, &tracked_id, "/tmp/example.txt");

    var list = try loadTracked(allocator, persistence);
    defer freeTrackedList(allocator, &list);

    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualSlices(u8, &tracked_id, list.items[0].id.asSlice());
    try std.testing.expectEqualStrings("/tmp/example.txt", list.items[0].path.asSlice());
}

test "deleteTracked moves tracked file into trash" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    const persistence = PersistenceLayout.init(omohi_dir);

    var tracked_id: [32]u8 = undefined;
    @memset(&tracked_id, 'c');
    try writeTracked(allocator, persistence, &tracked_id, "/tmp/file.txt");
    try deleteTracked(allocator, persistence, &tracked_id);

    const src = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.trackedPath(), &tracked_id });
    defer allocator.free(src);
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile(src, .{}));

    const dst = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.trackedTrashPath(), &tracked_id });
    defer allocator.free(dst);
    const bytes = try omohi_dir.readFileAlloc(allocator, dst, 128);
    defer allocator.free(bytes);
    try std.testing.expectEqualStrings("/tmp/file.txt", bytes);
}
