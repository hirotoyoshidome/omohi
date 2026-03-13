const std = @import("std");

const PersistenceLayout = @import("../object/persistence_layout.zig").PersistenceLayout;
const version = @import("../local/version.zig");

pub const expected_store_version: u32 = 1;

/// Validates store VERSION.
pub fn ensureStoreVersion(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
) !void {
    const persistence = PersistenceLayout.init(omohi_dir);

    const actual = version.readVersion(allocator, persistence) catch |err| switch (err) {
        error.FileNotFound => return error.MissingStoreVersion,
        error.InvalidVersion => return error.VersionMismatch,
        else => return err,
    };

    if (actual != expected_store_version) return error.VersionMismatch;
}

test "missing VERSION on empty store returns MissingStoreVersion" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    try std.testing.expectError(error.MissingStoreVersion, ensureStoreVersion(allocator, omohi_dir));
}

test "missing VERSION on non-empty store returns MissingStoreVersion" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    var marker = try omohi_dir.createFile("HEAD", .{});
    defer marker.close();
    try marker.writeAll("commitId=abc\n");

    try std.testing.expectError(
        error.MissingStoreVersion,
        ensureStoreVersion(allocator, omohi_dir),
    );
}

test "invalid VERSION maps to VersionMismatch" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    var file = try omohi_dir.createFile("VERSION", .{});
    defer file.close();
    try file.writeAll("invalid\n");

    try std.testing.expectError(
        error.VersionMismatch,
        ensureStoreVersion(allocator, omohi_dir),
    );
}

test "different VERSION returns VersionMismatch" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const persistence = PersistenceLayout.init(omohi_dir);
    try version.writeVersion(allocator, persistence, expected_store_version + 1);

    try std.testing.expectError(
        error.VersionMismatch,
        ensureStoreVersion(allocator, omohi_dir),
    );
}

test "matching VERSION passes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const persistence = PersistenceLayout.init(omohi_dir);
    try version.writeVersion(allocator, persistence, expected_store_version);
    try ensureStoreVersion(allocator, omohi_dir);
}
