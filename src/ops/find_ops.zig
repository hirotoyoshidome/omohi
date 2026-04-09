const std = @import("std");

const store_api = @import("../store/api.zig");

pub const CommitSummary = store_api.CommitSummary;
pub const CommitSummaryList = store_api.CommitSummaryList;

/// Finds commits by optional tag and local-time range filters.
pub fn find(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    tag_name: ?[]const u8,
    since_millis: ?i64,
    until_millis: ?i64,
    limit: usize,
) !CommitSummaryList {
    try store_api.ensureStoreVersion(allocator, omohi_dir);
    return store_api.find(allocator, omohi_dir, tag_name, since_millis, until_millis, limit);
}

// Releases the owned commit summary strings returned by `find`.
pub fn freeCommitSummaryList(allocator: std.mem.Allocator, list: *CommitSummaryList) void {
    store_api.freeCommitSummaryList(allocator, list);
}
