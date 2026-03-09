const std = @import("std");

const store_api = @import("../store/api.zig");

/// Removes a staged file entry from staging by source path.
pub fn rm(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    source_dir: std.fs.Dir,
    source_path: []const u8,
) !void {
    try store_api.ensureStoreVersion(allocator, omohi_dir, .{ .allow_bootstrap = false });
    try store_api.rm(allocator, omohi_dir, source_dir, source_path);
}
