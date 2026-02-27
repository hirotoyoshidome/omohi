const std = @import("std");

const atomic_write = @import("../atomic_write.zig");
const PersistenceLayout = @import("../../object/persistence_layout.zig").PersistenceLayout;

const max_version_file_size = 64;

pub fn writeVersion(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    version: u32,
) !void {
    const content = try std.fmt.allocPrint(allocator, "{d}\n", .{version});
    defer allocator.free(content);
    try atomic_write.atomicWrite(allocator, persistence.dir, persistence.versionPath(), content);
}

pub fn readVersion(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
) !u32 {
    const bytes = try persistence.dir.readFileAlloc(
        allocator,
        persistence.versionPath(),
        max_version_file_size,
    );
    defer allocator.free(bytes);

    const trimmed = std.mem.trim(u8, std.mem.trimRight(u8, bytes, "\r\n"), " \t");
    if (trimmed.len == 0) return error.InvalidVersion;
    return std.fmt.parseInt(u32, trimmed, 10) catch error.InvalidVersion;
}

pub fn ensureVersion(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    expected_version: u32,
) !void {
    const actual = try readVersion(allocator, persistence);
    if (actual != expected_version) return error.VersionMismatch;
}

test "writeVersion and readVersion round-trip schema version" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    const persistence = PersistenceLayout.init(omohi_dir);

    try writeVersion(allocator, persistence, 1);

    const actual = try readVersion(allocator, persistence);
    try std.testing.expectEqual(@as(u32, 1), actual);
}

test "ensureVersion detects schema mismatch" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    const persistence = PersistenceLayout.init(omohi_dir);

    try writeVersion(allocator, persistence, 2);
    try std.testing.expectError(error.VersionMismatch, ensureVersion(allocator, persistence, 1));
}
