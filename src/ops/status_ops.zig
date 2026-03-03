const std = @import("std");

const store_api = @import("../store/api.zig");
const version_guard = @import("./preflight/store_version_guard.zig");

pub const StatusKind = store_api.StatusKind;
pub const StatusEntry = store_api.StatusEntry;
pub const StatusList = store_api.StatusList;

/// Returns status entries for tracked files.
pub fn status(allocator: std.mem.Allocator, omohi_dir: std.fs.Dir) !StatusList {
    try version_guard.ensureStoreVersion(allocator, omohi_dir, .{ .allow_bootstrap = false });
    return store_api.status(allocator, omohi_dir);
}

pub fn freeStatusList(allocator: std.mem.Allocator, list: *StatusList) void {
    store_api.freeStatusList(allocator, list);
}
