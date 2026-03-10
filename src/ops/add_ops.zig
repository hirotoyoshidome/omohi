const std = @import("std");

const add_store = @import("../store/api.zig");
const commit_ops = @import("./commit_ops.zig");

/// Stages a file by writing staged entry/object data.
pub fn add(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    absolute_path: []const u8,
) !void {
    try add_store.ensureStoreVersion(allocator, omohi_dir, .{ .allow_bootstrap = false });
    try add_store.add(allocator, omohi_dir, absolute_path);
}

fn onlyFileNameInDir(dir: std.fs.Dir, path: []const u8, out: *[64]u8) !void {
    var target = try dir.openDir(path, .{ .iterate = true });
    defer target.close();

    var it = target.iterate();
    const first = (try it.next()) orelse return error.MissingFile;
    if (first.kind != .file) return error.InvalidEntry;
    if ((try it.next()) != null) return error.TooManyFiles;
    if (first.name.len != out.len) return error.InvalidHashLength;
    @memcpy(out, first.name);
}

fn stagedEntryIdFrom(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    staged_entries_path: []const u8,
) ![]u8 {
    var staged_hash: [64]u8 = undefined;
    try onlyFileNameInDir(dir, staged_entries_path, &staged_hash);
    return std.fmt.allocPrint(allocator, "{s}", .{staged_hash});
}

fn propertyValue(bytes: []const u8, key: []const u8) ?[]const u8 {
    var iter = std.mem.splitScalar(u8, bytes, '\n');
    while (iter.next()) |raw| {
        const line = std.mem.trim(u8, std.mem.trimRight(u8, raw, "\r"), " \t");
        if (line.len <= key.len or line[key.len] != '=') continue;
        if (!std.mem.startsWith(u8, line, key)) continue;
        return line[key.len + 1 ..];
    }
    return null;
}

test "add writes staged entry and staged object using content hash" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try add_store.ensureStoreVersion(allocator, omohi_dir, .{ .allow_bootstrap = true });

    const source_path = "memo.txt";
    const payload = "hello add";
    var source_file = try source_dir.createFile(source_path, .{});
    try source_file.writeAll(payload);
    source_file.close();

    const absolute_path = try source_dir.realpathAlloc(allocator, source_path);
    defer allocator.free(absolute_path);
    _ = try add_store.track(allocator, omohi_dir, absolute_path);

    try add(allocator, omohi_dir, absolute_path);

    var staged_object_hash: [64]u8 = undefined;
    try onlyFileNameInDir(omohi_dir, "staged/objects", &staged_object_hash);
    const object_path = try std.fmt.allocPrint(allocator, "staged/objects/{s}", .{staged_object_hash});
    defer allocator.free(object_path);
    const staged_object = try omohi_dir.readFileAlloc(allocator, object_path, 512);
    defer allocator.free(staged_object);
    try std.testing.expectEqualStrings(payload, staged_object);

    const staged_entry_id = try stagedEntryIdFrom(allocator, omohi_dir, "staged/entries");
    defer allocator.free(staged_entry_id);
    const entry_path = try std.fmt.allocPrint(allocator, "staged/entries/{s}", .{staged_entry_id});
    defer allocator.free(entry_path);
    const staged_entry = try omohi_dir.readFileAlloc(allocator, entry_path, 1024);
    defer allocator.free(staged_entry);

    const expected_path = try std.fmt.allocPrint(
        allocator,
        "path=/objects/{s}/{s}",
        .{ staged_object_hash[0..2], staged_object_hash },
    );
    defer allocator.free(expected_path);
    try std.testing.expect(std.mem.indexOf(u8, staged_entry, expected_path) != null);

    const expected_hash = try std.fmt.allocPrint(allocator, "contentHash={s}", .{staged_object_hash});
    defer allocator.free(expected_hash);
    try std.testing.expect(std.mem.indexOf(u8, staged_entry, expected_hash) != null);
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile("LOCK", .{}));
}

test "commit can read staged data created by add" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try add_store.ensureStoreVersion(allocator, omohi_dir, .{ .allow_bootstrap = true });

    const source_path = "notes.txt";
    const payload = "flow-check";
    var source_file = try source_dir.createFile(source_path, .{});
    try source_file.writeAll(payload);
    source_file.close();

    const absolute_path = try source_dir.realpathAlloc(allocator, source_path);
    defer allocator.free(absolute_path);
    _ = try add_store.track(allocator, omohi_dir, absolute_path);

    try add(allocator, omohi_dir, absolute_path);
    _ = try commit_ops.commit(allocator, omohi_dir, "via add");

    const head_bytes = try omohi_dir.readFileAlloc(allocator, "HEAD", 256);
    defer allocator.free(head_bytes);
    const commit_id = propertyValue(head_bytes, "commitId") orelse return error.MissingCommitId;

    const commit_path = try std.fmt.allocPrint(allocator, "commits/{s}/{s}", .{ commit_id[0..2], commit_id });
    defer allocator.free(commit_path);
    const commit_bytes = try omohi_dir.readFileAlloc(allocator, commit_path, 512);
    defer allocator.free(commit_bytes);
    const snapshot_id = propertyValue(commit_bytes, "snapshotId") orelse return error.MissingSnapshotId;

    const snapshot_path = try std.fmt.allocPrint(allocator, "snapshots/{s}/{s}", .{ snapshot_id[0..2], snapshot_id });
    defer allocator.free(snapshot_path);
    const snapshot_bytes = try omohi_dir.readFileAlloc(allocator, snapshot_path, 1024);
    defer allocator.free(snapshot_bytes);
    const hash_value = propertyValue(snapshot_bytes, "entry.0.contentHash") orelse return error.MissingContentHash;

    const object_path = try std.fmt.allocPrint(allocator, "objects/{s}/{s}", .{ hash_value[0..2], hash_value });
    defer allocator.free(object_path);
    const object_bytes = try omohi_dir.readFileAlloc(allocator, object_path, 512);
    defer allocator.free(object_bytes);
    try std.testing.expectEqualStrings(payload, object_bytes);
}
