const std = @import("std");

const store_api = @import("../store/api.zig");
const persistence_fixture_inspector = @import("../testing/persistence_fixture_inspector.zig");
pub const StringList = store_api.StringList;

/// Executes the durable commit transaction: lock -> persist data -> HEAD -> cleanup.
pub fn commit(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    message: []const u8,
    empty: bool,
) ![64]u8 {
    try store_api.ensureStoreVersion(allocator, omohi_dir);
    const id = try store_api.commit(allocator, omohi_dir, message, empty);
    return id.value;
}

/// Returns owned staged paths for commit dry-run preview.
pub fn stagedPaths(allocator: std.mem.Allocator, omohi_dir: std.fs.Dir) !StringList {
    try store_api.ensureStoreVersion(allocator, omohi_dir);
    return store_api.stagedPaths(allocator, omohi_dir);
}

// Releases owned strings returned by `stagedPaths`.
pub fn freeStringList(allocator: std.mem.Allocator, list: *StringList) void {
    store_api.freeStringList(allocator, list);
}

test "commit writes immutable data and cleans staged" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try store_api.initializeVersionForFirstTrack(allocator, omohi_dir);

    try omohi_dir.makePath("staged/entries");
    try omohi_dir.makePath("staged/objects");

    var content_hash: [64]u8 = undefined;
    @memset(&content_hash, 'a');

    const entry_text = try std.fmt.allocPrint(
        allocator,
        "path=/tmp/test-entry.txt\ntrackedFileId=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\ncontentHash={s}\n",
        .{content_hash},
    );
    defer allocator.free(entry_text);

    var entry_file = try omohi_dir.createFile("staged/entries/test-entry", .{});
    try entry_file.writeAll(entry_text);
    entry_file.close();

    const staged_object_path = try std.fmt.allocPrint(allocator, "staged/objects/{s}", .{content_hash});
    defer allocator.free(staged_object_path);

    var object_file = try omohi_dir.createFile(staged_object_path, .{});
    const payload = "payload-data";
    try object_file.writeAll(payload);
    object_file.close();

    const message = "initial commit";
    const commit_id = try commit(allocator, omohi_dir, message, false);

    const head_bytes = try omohi_dir.readFileAlloc(allocator, "HEAD", 256);
    defer allocator.free(head_bytes);
    const head_value = persistence_fixture_inspector.headValue(head_bytes);
    try std.testing.expect(head_value != null);
    const head_id = head_value.?;
    try std.testing.expectEqualSlices(u8, &commit_id, head_id);
    try std.testing.expectEqual(@as(usize, 64), head_id.len);

    const commit_path = try std.fmt.allocPrint(allocator, "commits/{s}/{s}", .{ head_id[0..2], head_id });
    defer allocator.free(commit_path);
    const commit_bytes = try omohi_dir.readFileAlloc(allocator, commit_path, 512);
    defer allocator.free(commit_bytes);
    const snapshot_value = persistence_fixture_inspector.propertyValue(commit_bytes, "snapshotId");
    try std.testing.expect(snapshot_value != null);
    const snapshot_id = snapshot_value.?;
    const message_value = persistence_fixture_inspector.propertyValue(commit_bytes, "message");
    try std.testing.expect(message_value != null);
    try std.testing.expectEqualStrings(message, message_value.?);
    try std.testing.expectEqual(@as(usize, 64), snapshot_id.len);

    const snapshot_path = try std.fmt.allocPrint(allocator, "snapshots/{s}/{s}", .{ snapshot_id[0..2], snapshot_id });
    defer allocator.free(snapshot_path);
    const snapshot_bytes = try omohi_dir.readFileAlloc(allocator, snapshot_path, 512);
    defer allocator.free(snapshot_bytes);
    const expected_snapshot_entry = try std.fmt.allocPrint(
        allocator,
        "entries=/tmp/test-entry.txt:{s}",
        .{content_hash},
    );
    defer allocator.free(expected_snapshot_entry);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_bytes, expected_snapshot_entry) != null);

    const objects_path = try std.fmt.allocPrint(allocator, "objects/{s}/{s}", .{ content_hash[0..2], content_hash });
    defer allocator.free(objects_path);
    const stored_object = try omohi_dir.readFileAlloc(allocator, objects_path, 512);
    defer allocator.free(stored_object);
    try std.testing.expectEqualStrings(payload, stored_object);

    try persistence_fixture_inspector.expectDirEmpty(omohi_dir, "staged/entries");
    try persistence_fixture_inspector.expectDirEmpty(omohi_dir, "staged/objects");
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile("LOCK", .{}));
}

test "commit without staged entries returns NothingToCommit and removes lock" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try store_api.initializeVersionForFirstTrack(std.testing.allocator, omohi_dir);
    try omohi_dir.makePath("staged/entries");
    try omohi_dir.makePath("staged/objects");

    try std.testing.expectError(error.NothingToCommit, commit(std.testing.allocator, omohi_dir, "msg", false));
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile("LOCK", .{}));
}

test "empty commit without staged entries writes message-only commit" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try store_api.initializeVersionForFirstTrack(allocator, omohi_dir);
    try omohi_dir.makePath("staged/entries");
    try omohi_dir.makePath("staged/objects");

    const commit_id = try commit(allocator, omohi_dir, "memo", true);

    const commit_path = try std.fmt.allocPrint(allocator, "commits/{s}/{s}", .{ commit_id[0..2], commit_id });
    defer allocator.free(commit_path);
    const commit_bytes = try omohi_dir.readFileAlloc(allocator, commit_path, 512);
    defer allocator.free(commit_bytes);
    try std.testing.expectEqualStrings("true", persistence_fixture_inspector.propertyValue(commit_bytes, "empty").?);

    const snapshot_id = persistence_fixture_inspector.propertyValue(commit_bytes, "snapshotId").?;
    const snapshot_path = try std.fmt.allocPrint(allocator, "snapshots/{s}/{s}", .{ snapshot_id[0..2], snapshot_id });
    defer allocator.free(snapshot_path);
    const snapshot_bytes = try omohi_dir.readFileAlloc(allocator, snapshot_path, 256);
    defer allocator.free(snapshot_bytes);
    try std.testing.expectEqualStrings("entries=\n", snapshot_bytes);

    try persistence_fixture_inspector.expectDirEmpty(omohi_dir, "staged/entries");
    try persistence_fixture_inspector.expectDirEmpty(omohi_dir, "staged/objects");
}
