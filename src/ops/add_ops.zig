const std = @import("std");

const add_store = @import("../store/api.zig");
const commit_ops = @import("./commit_ops.zig");
const status_ops = @import("./status_ops.zig");

pub const AddOutcome = struct {
    staged_paths: std.array_list.Managed([]u8),
    skipped_untracked: usize,
    skipped_missing: usize,
    skipped_non_regular: usize,
    skipped_already_staged: usize,
    skipped_no_change: usize,

    // Initializes an empty add outcome that owns its collected staged paths.
    pub fn init(allocator: std.mem.Allocator) AddOutcome {
        return .{
            .staged_paths = std.array_list.Managed([]u8).init(allocator),
            .skipped_untracked = 0,
            .skipped_missing = 0,
            .skipped_non_regular = 0,
            .skipped_already_staged = 0,
            .skipped_no_change = 0,
        };
    }
};

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

    var statuses = try status_ops.status(allocator, omohi_dir);
    defer status_ops.freeStatusList(allocator, &statuses);

    var outcome = AddOutcome.init(allocator);
    errdefer freeAddOutcome(allocator, &outcome);

    for (statuses.items) |entry| {
        if (entry.status != .tracked and entry.status != .changed) continue;

        var single = try addSingleFile(allocator, omohi_dir, entry.path);
        errdefer freeAddOutcome(allocator, &single);
        try adoptAddOutcome(&outcome, &single);
    }

    return outcome;
}

// Releases all owned staged path strings stored in the outcome.
pub fn freeAddOutcome(allocator: std.mem.Allocator, outcome: *AddOutcome) void {
    for (outcome.staged_paths.items) |path| allocator.free(path);
    outcome.staged_paths.deinit();
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
    const status_kind = try statusForPath(allocator, omohi_dir, absolute_path);
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
    var outcome = AddOutcome.init(allocator);
    errdefer freeAddOutcome(allocator, &outcome);

    var collected = std.array_list.Managed([]u8).init(allocator);
    defer {
        for (collected.items) |path| allocator.free(path);
        collected.deinit();
    }
    try collectRegularFiles(allocator, absolute_path, &collected, &outcome.skipped_non_regular);
    std.mem.sort([]u8, collected.items, {}, lessThanPath);

    const path_views = try allocator.alloc([]const u8, collected.items.len);
    defer allocator.free(path_views);
    for (collected.items, 0..) |path, idx| path_views[idx] = path;

    var batch = try add_store.addDirectory(allocator, omohi_dir, path_views);
    defer add_store.freeAddBatchOutcome(allocator, &batch);

    outcome.staged_paths.deinit();
    outcome.staged_paths = batch.staged_paths;
    batch.staged_paths = add_store.StringList.init(allocator);
    outcome.skipped_untracked = batch.skipped_untracked;
    outcome.skipped_missing = batch.skipped_missing;
    outcome.skipped_already_staged = batch.skipped_already_staged;
    outcome.skipped_no_change = batch.skipped_no_change;

    return outcome;
}

// Moves staged path ownership and counters into one combined add outcome.
fn adoptAddOutcome(combined: *AddOutcome, outcome: *AddOutcome) !void {
    combined.skipped_untracked += outcome.skipped_untracked;
    combined.skipped_missing += outcome.skipped_missing;
    combined.skipped_non_regular += outcome.skipped_non_regular;
    combined.skipped_already_staged += outcome.skipped_already_staged;
    combined.skipped_no_change += outcome.skipped_no_change;
    try combined.staged_paths.ensureUnusedCapacity(outcome.staged_paths.items.len);
    for (outcome.staged_paths.items) |path| {
        combined.staged_paths.appendAssumeCapacity(path);
    }
    outcome.staged_paths.items.len = 0;
    outcome.staged_paths.deinit();
}

// Recursively collects regular files below the absolute directory path.
fn collectRegularFiles(
    allocator: std.mem.Allocator,
    absolute_dir_path: []const u8,
    collected: *std.array_list.Managed([]u8),
    skipped_non_regular: *usize,
) !void {
    var dir = try std.fs.openDirAbsolute(absolute_dir_path, .{ .iterate = true, .access_sub_paths = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        const child_path = try std.fs.path.resolve(allocator, &.{ absolute_dir_path, entry.name });
        errdefer allocator.free(child_path);

        switch (entry.kind) {
            .file => try collected.append(child_path),
            .directory => {
                try collectRegularFiles(allocator, child_path, collected, skipped_non_regular);
                allocator.free(child_path);
            },
            else => {
                skipped_non_regular.* += 1;
                allocator.free(child_path);
            },
        }
    }
}

// Sorts collected absolute paths in ascending byte order.
fn lessThanPath(_: void, lhs: []u8, rhs: []u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

// Loads the current status for one path to classify add outcomes.
fn statusForPath(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    absolute_path: []const u8,
) !status_ops.StatusKind {
    var statuses = try status_ops.status(allocator, omohi_dir);
    defer status_ops.freeStatusList(allocator, &statuses);

    for (statuses.items) |entry| {
        if (std.mem.eql(u8, entry.path, absolute_path)) return entry.status;
    }
    return .tracked;
}

// Reads the single file name inside a directory and copies it into the fixed output buffer.
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

// Returns the staged entry file name as an owned string for test assertions.
fn stagedEntryIdFrom(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    staged_entries_path: []const u8,
) ![]u8 {
    var staged_hash: [64]u8 = undefined;
    try onlyFileNameInDir(dir, staged_entries_path, &staged_hash);
    return std.fmt.allocPrint(allocator, "{s}", .{staged_hash});
}

// Returns the value for a `key=value` property line when present.
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

// Returns the first non-empty HEAD line from the stored file bytes.
fn headValue(bytes: []const u8) ?[]const u8 {
    var iter = std.mem.splitScalar(u8, bytes, '\n');
    while (iter.next()) |raw| {
        const line = std.mem.trim(u8, std.mem.trimRight(u8, raw, "\r"), " \t");
        if (line.len == 0) continue;
        return line;
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
    _ = try commit_ops.commit(allocator, omohi_dir, "via add");

    const head_bytes = try omohi_dir.readFileAlloc(allocator, "HEAD", 256);
    defer allocator.free(head_bytes);
    const commit_id = headValue(head_bytes) orelse return error.MissingCommitId;

    const commit_path = try std.fmt.allocPrint(allocator, "commits/{s}/{s}", .{ commit_id[0..2], commit_id });
    defer allocator.free(commit_path);
    const commit_bytes = try omohi_dir.readFileAlloc(allocator, commit_path, 512);
    defer allocator.free(commit_bytes);
    const snapshot_id = propertyValue(commit_bytes, "snapshotId") orelse return error.MissingSnapshotId;

    const snapshot_path = try std.fmt.allocPrint(allocator, "snapshots/{s}/{s}", .{ snapshot_id[0..2], snapshot_id });
    defer allocator.free(snapshot_path);
    const snapshot_bytes = try omohi_dir.readFileAlloc(allocator, snapshot_path, 1024);
    defer allocator.free(snapshot_bytes);
    const entries_value = propertyValue(snapshot_bytes, "entries") orelse return error.MissingContentHash;
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
    _ = try commit_ops.commit(allocator, omohi_dir, "first");

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
    _ = try commit_ops.commit(allocator, omohi_dir, "first");

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
