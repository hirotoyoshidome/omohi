const std = @import("std");

const store_api = @import("../store/api.zig");
const local = @import("../store/local/persistence.zig");
const version_guard = @import("./preflight/store_version_guard.zig");

/// Registers an absolute file path as tracked.
pub fn track(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    absolute_path: []const u8,
) ![32]u8 {
    try version_guard.ensureStoreVersion(allocator, omohi_dir, .{ .allow_bootstrap = true });
    const id = try store_api.track(allocator, omohi_dir, absolute_path);
    return id.value;
}

/// Removes an existing tracked file id.
pub fn untrack(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    tracked_file_id: []const u8,
) !void {
    try version_guard.ensureStoreVersion(allocator, omohi_dir, .{ .allow_bootstrap = false });
    try store_api.untrack(allocator, omohi_dir, tracked_file_id);
}

/// Returns tracked id/path records.
pub fn tracklist(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
) !local.TrackedList {
    try version_guard.ensureStoreVersion(allocator, omohi_dir, .{ .allow_bootstrap = false });
    return store_api.tracklist(allocator, omohi_dir);
}

pub fn freeTracklist(allocator: std.mem.Allocator, list: *local.TrackedList) void {
    store_api.freeTracklist(allocator, list);
}

test "ops track and tracklist round-trip" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const tracked_id = try track(allocator, omohi_dir, "/tmp/ops-track.txt");

    var list = try tracklist(allocator, omohi_dir);
    defer freeTracklist(allocator, &list);

    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualSlices(u8, &tracked_id, list.items[0].id.asSlice());
    try std.testing.expectEqualStrings("/tmp/ops-track.txt", list.items[0].path.asSlice());
}

test "ops untrack removes tracked entry and propagates NotFound" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const tracked_id = try track(allocator, omohi_dir, "/tmp/ops-untrack.txt");
    try untrack(allocator, omohi_dir, &tracked_id);

    var list = try tracklist(allocator, omohi_dir);
    defer freeTracklist(allocator, &list);
    try std.testing.expectEqual(@as(usize, 0), list.items.len);

    try std.testing.expectError(error.NotFound, untrack(allocator, omohi_dir, &tracked_id));
}
