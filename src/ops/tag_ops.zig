const std = @import("std");

const store_api = @import("../store/api.zig");

pub const TagList = store_api.TagList;

/// Lists tags for a commit.
pub fn list(allocator: std.mem.Allocator, omohi_dir: std.fs.Dir, commit_id: []const u8) !TagList {
    try store_api.ensureStoreVersion(allocator, omohi_dir);
    return store_api.tagList(allocator, omohi_dir, commit_id);
}

// Releases the owned tag strings returned by tag queries.
pub fn freeTagList(allocator: std.mem.Allocator, tags: *TagList) void {
    store_api.freeTagList(allocator, tags);
}

/// Adds tags to a commit.
pub fn add(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    commit_id: []const u8,
    tag_names: []const []const u8,
) !void {
    try store_api.ensureStoreVersion(allocator, omohi_dir);
    try store_api.tagAdd(allocator, omohi_dir, commit_id, tag_names);
}

/// Removes tags from a commit.
pub fn rm(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    commit_id: []const u8,
    tag_names: []const []const u8,
) !void {
    try store_api.ensureStoreVersion(allocator, omohi_dir);
    try store_api.tagRemove(allocator, omohi_dir, commit_id, tag_names);
}
