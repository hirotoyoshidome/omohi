const std = @import("std");

const store_api = @import("../store/api.zig");

/// Default archive size limit for the backup command.
pub const default_max_size: u64 = 1024 * 1024 * 1024;

/// Describes a completed backup archive.
pub const BackupResult = store_api.BackupResult;

/// Creates a full backup archive for the current store.
pub fn backup(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    store_path: []const u8,
    archive_path: []const u8,
    max_size: u64,
) !BackupResult {
    return store_api.backupStore(allocator, omohi_dir, store_path, archive_path, max_size);
}

test "backup delegates to store and creates an archive" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try omohi_dir.writeFile(.{ .sub_path = "VERSION", .data = "1\n" });

    const store_path = try tmp.dir.realpathAlloc(allocator, ".omohi");
    defer allocator.free(store_path);
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    const archive_path = try std.fs.path.join(allocator, &.{ tmp_path, "backup.tar.gz" });
    defer allocator.free(archive_path);

    const result = try backup(allocator, omohi_dir, store_path, archive_path, default_max_size);
    try std.testing.expect(result.archive_size > 0);
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile("LOCK", .{}));
}
