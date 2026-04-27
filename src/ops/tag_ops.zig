const std = @import("std");

const store_api = @import("../store/api.zig");
const test_support = @import("../testing/store_api_test_support.zig");

pub const TagList = store_api.TagList;
pub const TagNameList = store_api.StringList;

/// Lists all known tag names.
pub fn listAll(allocator: std.mem.Allocator, omohi_dir: std.fs.Dir) !TagNameList {
    try store_api.ensureStoreVersion(allocator, omohi_dir);
    return store_api.tagNameList(allocator, omohi_dir);
}

/// Lists tags for a commit.
pub fn list(allocator: std.mem.Allocator, omohi_dir: std.fs.Dir, commit_id: []const u8) !TagList {
    try store_api.ensureStoreVersion(allocator, omohi_dir);
    return store_api.tagList(allocator, omohi_dir, commit_id);
}

// Releases the owned tag strings returned by tag queries.
pub fn freeTagList(allocator: std.mem.Allocator, tags: *TagList) void {
    store_api.freeTagList(allocator, tags);
}

// Releases the owned tag strings returned by global tag queries.
pub fn freeTagNameList(allocator: std.mem.Allocator, tags: *TagNameList) void {
    store_api.freeStringList(allocator, tags);
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

test "listAll returns known tag names sorted ascending" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    try store_api.initializeVersionForFirstTrack(allocator, omohi_dir);
    const tracked_path = try test_support.addTestFileForCommit(tmp.dir, allocator, "a.txt", "one");
    defer allocator.free(tracked_path);

    _ = try store_api.track(allocator, omohi_dir, tracked_path);
    try store_api.add(allocator, omohi_dir, tracked_path);
    const commit_id = try store_api.commit(allocator, omohi_dir, "first", false);
    try store_api.tagAdd(allocator, omohi_dir, commit_id.asSlice(), &.{ "release", "alpha" });

    var tags = try listAll(allocator, omohi_dir);
    defer freeTagNameList(allocator, &tags);

    try std.testing.expectEqual(@as(usize, 2), tags.items.len);
    try std.testing.expectEqualStrings("alpha", tags.items[0]);
    try std.testing.expectEqualStrings("release", tags.items[1]);
}
