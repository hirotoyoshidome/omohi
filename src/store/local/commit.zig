const std = @import("std");

const atomic_write = @import("../storage/atomic_write.zig");
const PersistenceLayout = @import("../object/persistence_layout.zig").PersistenceLayout;
const utc = @import("../storage/time/utc.zig");

// Persists one commit record using atomic write semantics.
pub fn writeCommit(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    commit_id: []const u8,
    snapshot_id: []const u8,
    message: []const u8,
) !void {
    const created_at = try utc.nowIso8601Utc();
    const content = try formatCommitFile(allocator, snapshot_id, message, created_at);
    defer allocator.free(content);

    const path = try persistence.commitsPath(allocator, commit_id);
    defer allocator.free(path);

    try atomic_write.atomicWrite(allocator, persistence.dir, path, content);
}

// Formats a commit record into owned file contents for the caller to free.
fn formatCommitFile(
    allocator: std.mem.Allocator,
    snapshot_id: []const u8,
    message: []const u8,
    created_at: [24]u8,
) ![]u8 {
    var buffer = std.array_list.Managed(u8).init(allocator);
    defer buffer.deinit();

    var writer = buffer.writer();
    try writer.print("snapshotId={s}\n", .{snapshot_id});
    try writer.print("message={s}\n", .{message});
    try writer.print("createdAt={s}\n", .{created_at});
    return buffer.toOwnedSlice();
}

test "formatCommitFile renders commit properties" {
    const allocator = std.testing.allocator;
    var snapshot_id: [64]u8 = undefined;
    @memset(&snapshot_id, 'd');
    const created_at = "2024-01-02T03:04:05.006Z".*;
    const result = try formatCommitFile(allocator, &snapshot_id, "message", created_at);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "snapshotId=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "message=message") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "createdAt=2024-01-02T03:04:05.006Z") != null);
}

test "writeCommit persists commit file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    var persistence = PersistenceLayout.init(omohi_dir);
    var snapshot_id: [64]u8 = undefined;
    @memset(&snapshot_id, 'e');
    var commit_id: [64]u8 = undefined;
    @memset(&commit_id, 'f');

    try writeCommit(allocator, persistence, &commit_id, &snapshot_id, "initial");

    const path = try persistence.commitsPath(allocator, &commit_id);
    defer allocator.free(path);

    const content = try omohi_dir.readFileAlloc(allocator, path, 1024);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "snapshotId=") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "message=initial") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "createdAt=") != null);
}
