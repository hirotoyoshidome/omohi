const std = @import("std");

const add_store = @import("../store/api.zig");
pub const AddOutcome = add_store.AddBatchOutcome;

/// Stages a file by writing staged entry/object data.
pub fn add(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    absolute_path: []const u8,
) !AddOutcome {
    try add_store.ensureStoreVersion(allocator, omohi_dir);

    var dir = std.fs.openDirAbsolute(absolute_path, .{ .iterate = true, .access_sub_paths = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return addSingleFile(allocator, omohi_dir, absolute_path),
        else => return err,
    };
    defer dir.close();

    return addDirectory(allocator, omohi_dir, absolute_path);
}

/// Stages all tracked files currently listed in the status changed-tracked section.
pub fn addAllTracked(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
) !AddOutcome {
    try add_store.ensureStoreVersion(allocator, omohi_dir);
    return add_store.addAllTracked(allocator, omohi_dir);
}

// Releases all owned staged path strings stored in the outcome.
pub fn freeAddOutcome(allocator: std.mem.Allocator, outcome: *AddOutcome) void {
    add_store.freeAddBatchOutcome(allocator, outcome);
}

// Stages one tracked file and reports whether it became staged or was already committed.
fn addSingleFile(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    absolute_path: []const u8,
) !AddOutcome {
    try add_store.add(allocator, omohi_dir, absolute_path);

    var outcome = AddOutcome.init(allocator);
    errdefer freeAddOutcome(allocator, &outcome);
    const status_kind = try add_store.statusForTrackedPath(allocator, omohi_dir, absolute_path);
    if (status_kind == .staged) {
        try outcome.staged_paths.append(try allocator.dupe(u8, absolute_path));
    } else if (status_kind == .committed) {
        outcome.skipped_no_change = 1;
    }
    return outcome;
}

// Stages every regular file under the directory and reports skipped-path counters.
fn addDirectory(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    absolute_path: []const u8,
) !AddOutcome {
    return add_store.addTree(allocator, omohi_dir, absolute_path);
}

// Returns the staged entry file name as an owned string for test assertions.
fn stagedEntryIdFrom(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    staged_entries_path: []const u8,
) ![]u8 {
    var staged_hash: [64]u8 = undefined;
    try add_store.testOnlyOnlyFileNameInDir(dir, staged_entries_path, &staged_hash);
    return std.fmt.allocPrint(allocator, "{s}", .{staged_hash});
}

test "add writes staged entry and staged object using content hash" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try add_store.initializeVersionForFirstTrack(allocator, omohi_dir);

    const source_path = "memo.txt";
    const payload = "hello add";
    var source_file = try source_dir.createFile(source_path, .{});
    try source_file.writeAll(payload);
    source_file.close();

    const absolute_path = try source_dir.realpathAlloc(allocator, source_path);
    defer allocator.free(absolute_path);
    _ = try add_store.track(allocator, omohi_dir, absolute_path);

    var outcome = try add(allocator, omohi_dir, absolute_path);
    defer freeAddOutcome(allocator, &outcome);

    var staged_object_hash: [64]u8 = undefined;
    try add_store.testOnlyOnlyFileNameInDir(omohi_dir, "staged/objects", &staged_object_hash);
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
        "path={s}",
        .{absolute_path},
    );
    defer allocator.free(expected_path);
    try std.testing.expect(std.mem.indexOf(u8, staged_entry, expected_path) != null);

    try std.testing.expect(std.mem.indexOf(u8, staged_entry, "trackedFileId=") != null);
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
    try add_store.initializeVersionForFirstTrack(allocator, omohi_dir);

    const source_path = "notes.txt";
    const payload = "flow-check";
    var source_file = try source_dir.createFile(source_path, .{});
    try source_file.writeAll(payload);
    source_file.close();

    const absolute_path = try source_dir.realpathAlloc(allocator, source_path);
    defer allocator.free(absolute_path);
    _ = try add_store.track(allocator, omohi_dir, absolute_path);

    var outcome = try add(allocator, omohi_dir, absolute_path);
    defer freeAddOutcome(allocator, &outcome);
    _ = try add_store.commit(allocator, omohi_dir, "via add");

    const head_bytes = try omohi_dir.readFileAlloc(allocator, "HEAD", 256);
    defer allocator.free(head_bytes);
    const commit_id = add_store.testOnlyHeadValue(head_bytes) orelse return error.MissingCommitId;

    const commit_path = try std.fmt.allocPrint(allocator, "commits/{s}/{s}", .{ commit_id[0..2], commit_id });
    defer allocator.free(commit_path);
    const commit_bytes = try omohi_dir.readFileAlloc(allocator, commit_path, 512);
    defer allocator.free(commit_bytes);
    const snapshot_id = add_store.testOnlyPropertyValue(commit_bytes, "snapshotId") orelse return error.MissingSnapshotId;

    const snapshot_path = try std.fmt.allocPrint(allocator, "snapshots/{s}/{s}", .{ snapshot_id[0..2], snapshot_id });
    defer allocator.free(snapshot_path);
    const snapshot_bytes = try omohi_dir.readFileAlloc(allocator, snapshot_path, 1024);
    defer allocator.free(snapshot_bytes);
    const entries_value = add_store.testOnlyPropertyValue(snapshot_bytes, "entries") orelse return error.MissingContentHash;
    const separator = std.mem.lastIndexOfScalar(u8, entries_value, ':') orelse return error.MissingContentHash;
    if (separator + 1 >= entries_value.len) return error.MissingContentHash;
    const hash_value = entries_value[separator + 1 ..];

    const object_path = try std.fmt.allocPrint(allocator, "objects/{s}/{s}", .{ hash_value[0..2], hash_value });
    defer allocator.free(object_path);
    const object_bytes = try omohi_dir.readFileAlloc(allocator, object_path, 512);
    defer allocator.free(object_bytes);
    try std.testing.expectEqualStrings(payload, object_bytes);
}

test "add stages tracked files recursively and skips untracked files under directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try add_store.initializeVersionForFirstTrack(allocator, omohi_dir);

    try source_dir.makePath("nested");
    {
        var file = try source_dir.createFile("a.txt", .{});
        defer file.close();
        try file.writeAll("a");
    }
    {
        var file = try source_dir.createFile("nested/b.txt", .{});
        defer file.close();
        try file.writeAll("b");
    }
    {
        var file = try source_dir.createFile("nested/c.txt", .{});
        defer file.close();
        try file.writeAll("c");
    }

    const a_path = try source_dir.realpathAlloc(allocator, "a.txt");
    defer allocator.free(a_path);
    const b_path = try source_dir.realpathAlloc(allocator, "nested/b.txt");
    defer allocator.free(b_path);
    const root_path = try source_dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    _ = try add_store.track(allocator, omohi_dir, a_path);
    _ = try add_store.track(allocator, omohi_dir, b_path);

    var outcome = try add(allocator, omohi_dir, root_path);
    defer freeAddOutcome(allocator, &outcome);

    try std.testing.expectEqual(@as(usize, 2), outcome.staged_paths.items.len);
    try std.testing.expectEqual(@as(usize, 1), outcome.skipped_untracked);
    try std.testing.expectEqual(@as(usize, 0), outcome.skipped_already_staged);
    try std.testing.expectEqual(@as(usize, 0), outcome.skipped_no_change);
}

test "add skips files already staged with current content when directory is given" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try add_store.initializeVersionForFirstTrack(allocator, omohi_dir);

    try source_dir.makePath("nested");
    {
        var file = try source_dir.createFile("a.txt", .{});
        defer file.close();
        try file.writeAll("a");
    }
    {
        var file = try source_dir.createFile("nested/b.txt", .{});
        defer file.close();
        try file.writeAll("b");
    }

    const a_path = try source_dir.realpathAlloc(allocator, "a.txt");
    defer allocator.free(a_path);
    const b_path = try source_dir.realpathAlloc(allocator, "nested/b.txt");
    defer allocator.free(b_path);
    const root_path = try source_dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    _ = try add_store.track(allocator, omohi_dir, a_path);
    _ = try add_store.track(allocator, omohi_dir, b_path);

    try add_store.add(allocator, omohi_dir, a_path);

    var outcome = try add(allocator, omohi_dir, root_path);
    defer freeAddOutcome(allocator, &outcome);

    try std.testing.expectEqual(@as(usize, 1), outcome.staged_paths.items.len);
    try std.testing.expectEqual(@as(usize, 1), outcome.skipped_already_staged);
    try std.testing.expectEqual(@as(usize, 0), outcome.skipped_no_change);
}

test "add reports no-change when file matches HEAD" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try add_store.initializeVersionForFirstTrack(allocator, omohi_dir);

    var file = try source_dir.createFile("a.txt", .{});
    try file.writeAll("a");
    file.close();

    const absolute_path = try source_dir.realpathAlloc(allocator, "a.txt");
    defer allocator.free(absolute_path);

    _ = try add_store.track(allocator, omohi_dir, absolute_path);
    var initial_outcome = try add(allocator, omohi_dir, absolute_path);
    defer freeAddOutcome(allocator, &initial_outcome);
    _ = try add_store.commit(allocator, omohi_dir, "first");

    var outcome = try add(allocator, omohi_dir, absolute_path);
    defer freeAddOutcome(allocator, &outcome);

    try std.testing.expectEqual(@as(usize, 0), outcome.staged_paths.items.len);
    try std.testing.expectEqual(@as(usize, 1), outcome.skipped_no_change);
}

test "addAllTracked stages tracked files from status changed tracked group" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try add_store.initializeVersionForFirstTrack(allocator, omohi_dir);

    {
        var file = try source_dir.createFile("a.txt", .{});
        defer file.close();
        try file.writeAll("a");
    }
    try source_dir.makePath("nested");
    {
        var file = try source_dir.createFile("nested/b.txt", .{});
        defer file.close();
        try file.writeAll("b");
    }

    const a_path = try source_dir.realpathAlloc(allocator, "a.txt");
    defer allocator.free(a_path);
    const b_path = try source_dir.realpathAlloc(allocator, "nested/b.txt");
    defer allocator.free(b_path);

    _ = try add_store.track(allocator, omohi_dir, a_path);
    _ = try add_store.track(allocator, omohi_dir, b_path);

    var outcome = try addAllTracked(allocator, omohi_dir);
    defer freeAddOutcome(allocator, &outcome);

    try std.testing.expectEqual(@as(usize, 2), outcome.staged_paths.items.len);
    const first_matches_a = std.mem.eql(u8, outcome.staged_paths.items[0], a_path);
    const first_matches_b = std.mem.eql(u8, outcome.staged_paths.items[0], b_path);
    const second_matches_a = std.mem.eql(u8, outcome.staged_paths.items[1], a_path);
    const second_matches_b = std.mem.eql(u8, outcome.staged_paths.items[1], b_path);
    try std.testing.expect(first_matches_a or first_matches_b);
    try std.testing.expect(second_matches_a or second_matches_b);
    try std.testing.expect(first_matches_a != second_matches_a);
    try std.testing.expect(first_matches_b != second_matches_b);
    try std.testing.expectEqual(@as(usize, 0), outcome.skipped_untracked);
    try std.testing.expectEqual(@as(usize, 0), outcome.skipped_already_staged);
    try std.testing.expectEqual(@as(usize, 0), outcome.skipped_no_change);
}

test "addAllTracked skips committed and already staged files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try add_store.initializeVersionForFirstTrack(allocator, omohi_dir);

    {
        var file = try source_dir.createFile("a.txt", .{});
        defer file.close();
        try file.writeAll("a");
    }
    {
        var file = try source_dir.createFile("b.txt", .{});
        defer file.close();
        try file.writeAll("b");
    }

    const a_path = try source_dir.realpathAlloc(allocator, "a.txt");
    defer allocator.free(a_path);
    const b_path = try source_dir.realpathAlloc(allocator, "b.txt");
    defer allocator.free(b_path);

    _ = try add_store.track(allocator, omohi_dir, a_path);
    _ = try add_store.track(allocator, omohi_dir, b_path);

    {
        var first = try add(allocator, omohi_dir, a_path);
        defer freeAddOutcome(allocator, &first);
    }
    _ = try add_store.commit(allocator, omohi_dir, "first");

    try add_store.add(allocator, omohi_dir, b_path);

    var outcome = try addAllTracked(allocator, omohi_dir);
    defer freeAddOutcome(allocator, &outcome);

    try std.testing.expectEqual(@as(usize, 0), outcome.staged_paths.items.len);
    try std.testing.expectEqual(@as(usize, 0), outcome.skipped_untracked);
    try std.testing.expectEqual(@as(usize, 0), outcome.skipped_already_staged);
    try std.testing.expectEqual(@as(usize, 0), outcome.skipped_no_change);
}

test "addAllTracked skips missing tracked files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try add_store.initializeVersionForFirstTrack(allocator, omohi_dir);

    {
        var file = try source_dir.createFile("a.txt", .{});
        defer file.close();
        try file.writeAll("a");
    }
    {
        var file = try source_dir.createFile("b.txt", .{});
        defer file.close();
        try file.writeAll("b");
    }

    const a_path = try source_dir.realpathAlloc(allocator, "a.txt");
    defer allocator.free(a_path);
    const b_path = try source_dir.realpathAlloc(allocator, "b.txt");
    defer allocator.free(b_path);

    _ = try add_store.track(allocator, omohi_dir, a_path);
    _ = try add_store.track(allocator, omohi_dir, b_path);
    try source_dir.deleteFile("b.txt");

    var outcome = try addAllTracked(allocator, omohi_dir);
    defer freeAddOutcome(allocator, &outcome);

    try std.testing.expectEqual(@as(usize, 1), outcome.staged_paths.items.len);
    try std.testing.expectEqualStrings(a_path, outcome.staged_paths.items[0]);
    try std.testing.expectEqual(@as(usize, 0), outcome.skipped_missing);
}
