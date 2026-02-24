const std = @import("std");

const atomic_write = @import("../atomic_write.zig");
const trash = @import("./trash.zig");
const PersistenceLayout = @import("../../object/persistence_layout.zig").PersistenceLayout;
const constrained_types = @import("../../object/constrained_types.zig");

const max_tag_file_size = 256;

pub fn writeTag(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    tag_name: []const u8,
    created_at: []const u8,
) !void {
    try validateTagFileName(tag_name);
    const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.dataTagsPath(), tag_name });
    defer allocator.free(path);
    try atomic_write.atomicWrite(allocator, persistence.dir, path, created_at);
}

pub fn readTagCreatedAt(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    tag_name: []const u8,
) ![]u8 {
    try validateTagFileName(tag_name);
    const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.dataTagsPath(), tag_name });
    defer allocator.free(path);
    const bytes = try persistence.dir.readFileAlloc(allocator, path, max_tag_file_size);
    errdefer allocator.free(bytes);
    const trimmed = std.mem.trimRight(u8, bytes, "\r\n");
    const out = try allocator.dupe(u8, trimmed);
    allocator.free(bytes);
    return out;
}

pub fn deleteTag(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    tag_name: []const u8,
) !void {
    try trash.moveTagToTrash(allocator, persistence, tag_name);
}

fn validateTagFileName(tag_name: []const u8) !void {
    _ = try constrained_types.TagName.init(tag_name);
    if (std.mem.indexOfScalar(u8, tag_name, '/')) |_| return error.InvalidTagName;
    if (std.mem.indexOf(u8, tag_name, "..")) |_| return error.InvalidTagName;
}

test "writeTag and readTagCreatedAt round-trip tag timestamp" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    const persistence = PersistenceLayout.init(omohi_dir);

    try writeTag(allocator, persistence, "release-1", "2026-02-24T00:00:00.000Z");

    const created_at = try readTagCreatedAt(allocator, persistence, "release-1");
    defer allocator.free(created_at);
    try std.testing.expectEqualStrings("2026-02-24T00:00:00.000Z", created_at);
}

test "deleteTag moves tag file into trash" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    const persistence = PersistenceLayout.init(omohi_dir);

    try writeTag(allocator, persistence, "prod", "2026-02-24T01:00:00.000Z");
    try deleteTag(allocator, persistence, "prod");

    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile("data/tags/prod", .{}));
    const bytes = try omohi_dir.readFileAlloc(allocator, "data/tags/.trash/prod", 256);
    defer allocator.free(bytes);
    try std.testing.expectEqualStrings("2026-02-24T01:00:00.000Z", bytes);
}
