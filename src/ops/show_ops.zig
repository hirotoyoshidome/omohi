const std = @import("std");

const store_api = @import("../store/api.zig");
const version_guard = @import("./preflight/store_version_guard.zig");

pub const CommitDetails = store_api.CommitDetails;

/// Returns one commit details payload.
pub fn show(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    commit_id: []const u8,
) !CommitDetails {
    try version_guard.ensureStoreVersion(allocator, omohi_dir, .{ .allow_bootstrap = false });
    return store_api.show(allocator, omohi_dir, commit_id);
}

pub fn freeCommitDetails(allocator: std.mem.Allocator, details: *CommitDetails) void {
    store_api.freeCommitDetails(allocator, details);
}
