const std = @import("std");

const store_api = @import("../store/api.zig");

pub const CommitDetails = store_api.CommitDetails;

/// Returns one commit details payload.
pub fn show(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    commit_id: []const u8,
) !CommitDetails {
    try store_api.ensureStoreVersion(allocator, omohi_dir);
    return store_api.show(allocator, omohi_dir, commit_id);
}

// Releases the owned strings contained in one commit details payload.
pub fn freeCommitDetails(allocator: std.mem.Allocator, details: *CommitDetails) void {
    store_api.freeCommitDetails(allocator, details);
}
