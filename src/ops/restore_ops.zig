const std = @import("std");

const store_api = @import("../store/api.zig");

/// Default archive and extracted size limit for the restore command.
pub const default_max_size: u64 = 1024 * 1024 * 1024;

/// Describes a completed restore operation.
pub const RestoreResult = store_api.RestoreResult;

/// Restores a full backup archive into the current user-level store.
pub fn restore(
    allocator: std.mem.Allocator,
    store_path: []const u8,
    archive_path: []const u8,
    replace_existing: bool,
    max_size: u64,
) !RestoreResult {
    return store_api.restoreStore(allocator, store_path, archive_path, replace_existing, max_size);
}

/// Releases owned memory from a restore result.
pub fn freeRestoreResult(allocator: std.mem.Allocator, result: *RestoreResult) void {
    store_api.freeRestoreResult(allocator, result);
}
