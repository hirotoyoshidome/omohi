const std = @import("std");

const store_api = @import("../store/api.zig");

/// Removes a staged file entry from staging by source path.
pub fn rm(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    absolute_path: []const u8,
) !void {
    try store_api.ensureStoreVersion(allocator, omohi_dir, .{ .allow_bootstrap = false });
    try store_api.rm(allocator, omohi_dir, absolute_path);
}

test "rm removes staged entry for tracked file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try store_api.ensureStoreVersion(allocator, omohi_dir, .{ .allow_bootstrap = true });

    var file = try source_dir.createFile("memo.txt", .{});
    try file.writeAll("hello");
    file.close();

    const absolute_path = try source_dir.realpathAlloc(allocator, "memo.txt");
    defer allocator.free(absolute_path);

    _ = try store_api.track(allocator, omohi_dir, absolute_path);
    try store_api.add(allocator, omohi_dir, absolute_path);
    try rm(allocator, omohi_dir, absolute_path);

    var entries = try omohi_dir.openDir("staged/entries", .{ .iterate = true });
    defer entries.close();
    var it = entries.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .file) return error.ExpectedNoStagedEntryFiles;
    }
}

test "rm propagates staged-not-found for tracked but unstaged path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try store_api.ensureStoreVersion(allocator, omohi_dir, .{ .allow_bootstrap = true });

    var file = try source_dir.createFile("memo.txt", .{});
    try file.writeAll("hello");
    file.close();

    const absolute_path = try source_dir.realpathAlloc(allocator, "memo.txt");
    defer allocator.free(absolute_path);
    _ = try store_api.track(allocator, omohi_dir, absolute_path);

    try std.testing.expectError(error.StagedFileNotFound, rm(allocator, omohi_dir, absolute_path));
}
