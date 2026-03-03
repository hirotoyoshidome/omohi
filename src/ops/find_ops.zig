const std = @import("std");

const store_api = @import("../store/api.zig");
const version_guard = @import("./preflight/store_version_guard.zig");

pub const CommitSummary = store_api.CommitSummary;
pub const CommitSummaryList = store_api.CommitSummaryList;

/// Finds commits by optional tag/date filters.
pub fn find(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    tag_name: ?[]const u8,
    date_prefix: ?[]const u8,
) !CommitSummaryList {
    try version_guard.ensureStoreVersion(allocator, omohi_dir, .{ .allow_bootstrap = false });
    return store_api.find(allocator, omohi_dir, tag_name, date_prefix);
}

pub fn freeCommitSummaryList(allocator: std.mem.Allocator, list: *CommitSummaryList) void {
    store_api.freeCommitSummaryList(allocator, list);
}
