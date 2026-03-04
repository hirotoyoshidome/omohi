const std = @import("std");

const local_persistence = @import("../../store/local/persistence.zig");

pub const expected_store_version: u32 = 1;

pub const Options = struct {
    allow_bootstrap: bool,
};

/// Validates store VERSION and optionally bootstraps VERSION=1 for a newly created empty store.
pub fn ensureStoreVersion(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    options: Options,
) !void {
    const persistence = local_persistence.PersistenceLayout.init(omohi_dir);

    const actual = local_persistence.read_version(allocator, persistence) catch |err| switch (err) {
        error.FileNotFound => {
            if (!options.allow_bootstrap) return error.VersionMismatch;
            if (!try isStoreEmpty(omohi_dir)) return error.VersionMismatch;
            try local_persistence.write_version(allocator, persistence, expected_store_version);
            return;
        },
        error.InvalidVersion => return error.VersionMismatch,
        else => return err,
    };

    if (actual != expected_store_version) return error.VersionMismatch;
}

fn isStoreEmpty(omohi_dir: std.fs.Dir) !bool {
    var it = omohi_dir.iterate();
    while (try it.next()) |_| return false;
    return true;
}

test "bootstrap writes VERSION for empty store when allowed" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    try ensureStoreVersion(allocator, omohi_dir, .{ .allow_bootstrap = true });

    const persistence = local_persistence.PersistenceLayout.init(omohi_dir);
    const actual = try local_persistence.read_version(allocator, persistence);
    try std.testing.expectEqual(expected_store_version, actual);
}

test "missing VERSION on non-empty store returns VersionMismatch" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    var marker = try omohi_dir.createFile("HEAD", .{});
    defer marker.close();
    try marker.writeAll("commitId=abc\n");

    try std.testing.expectError(
        error.VersionMismatch,
        ensureStoreVersion(allocator, omohi_dir, .{ .allow_bootstrap = true }),
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
        ensureStoreVersion(allocator, omohi_dir, .{ .allow_bootstrap = false }),
    );
}

test "different VERSION returns VersionMismatch" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const persistence = local_persistence.PersistenceLayout.init(omohi_dir);
    try local_persistence.write_version(allocator, persistence, expected_store_version + 1);

    try std.testing.expectError(
        error.VersionMismatch,
        ensureStoreVersion(allocator, omohi_dir, .{ .allow_bootstrap = false }),
    );
}

test "matching VERSION passes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const persistence = local_persistence.PersistenceLayout.init(omohi_dir);
    try local_persistence.write_version(allocator, persistence, expected_store_version);
    try ensureStoreVersion(allocator, omohi_dir, .{ .allow_bootstrap = false });
}
