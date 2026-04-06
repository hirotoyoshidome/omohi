const std = @import("std");

const store_api = @import("../store/api.zig");

pub const TrackedList = store_api.TrackedList;
pub const TrackOutcome = struct {
    tracked_paths: std.array_list.Managed([]u8),
    skipped_paths: usize,

    // Initializes an empty track outcome that owns its collected tracked paths.
    pub fn init(allocator: std.mem.Allocator) TrackOutcome {
        return .{
            .tracked_paths = std.array_list.Managed([]u8).init(allocator),
            .skipped_paths = 0,
        };
    }
};

pub const UntrackMissingOutcome = struct {
    untracked_paths: std.array_list.Managed([]u8),

    // Initializes an empty missing-untrack outcome that owns its path list.
    pub fn init(allocator: std.mem.Allocator) UntrackMissingOutcome {
        return .{
            .untracked_paths = std.array_list.Managed([]u8).init(allocator),
        };
    }
};

/// Registers an absolute path as tracked.
/// Directories are expanded recursively into regular files.
pub fn track(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    absolute_path: []const u8,
) !TrackOutcome {
    try store_api.initializeVersionForFirstTrack(allocator, omohi_dir);
    try store_api.ensureStoreVersion(allocator, omohi_dir);

    var dir = std.fs.openDirAbsolute(absolute_path, .{ .iterate = true, .access_sub_paths = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return trackSingleFile(allocator, omohi_dir, absolute_path),
        else => return err,
    };
    defer dir.close();

    return trackDirectory(allocator, omohi_dir, absolute_path);
}

/// Removes an existing tracked file id.
pub fn untrack(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    tracked_file_id: []const u8,
) !void {
    try store_api.ensureStoreVersion(allocator, omohi_dir);
    try store_api.untrack(allocator, omohi_dir, tracked_file_id);
}

/// Removes every tracked file currently reported as missing by `status`.
pub fn untrackMissing(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
) !UntrackMissingOutcome {
    try store_api.ensureStoreVersion(allocator, omohi_dir);

    var statuses = try store_api.status(allocator, omohi_dir);
    defer store_api.freeStatusList(allocator, &statuses);

    var outcome = UntrackMissingOutcome.init(allocator);
    errdefer freeUntrackMissingOutcome(allocator, &outcome);

    for (statuses.items) |entry| {
        if (entry.status != .missing) continue;
        try store_api.untrack(allocator, omohi_dir, entry.id.asSlice());
        try outcome.untracked_paths.append(try allocator.dupe(u8, entry.path));
    }

    return outcome;
}

/// Returns tracked id/path records.
pub fn tracklist(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
) !TrackedList {
    try store_api.ensureStoreVersion(allocator, omohi_dir);
    return store_api.tracklist(allocator, omohi_dir);
}

// Releases the owned tracked id/path records returned by `tracklist`.
pub fn freeTracklist(allocator: std.mem.Allocator, list: *TrackedList) void {
    store_api.freeTracklist(allocator, list);
}

// Releases the owned missing tracked paths stored in the outcome.
pub fn freeUntrackMissingOutcome(allocator: std.mem.Allocator, outcome: *UntrackMissingOutcome) void {
    for (outcome.untracked_paths.items) |path| allocator.free(path);
    outcome.untracked_paths.deinit();
}

// Releases the owned tracked path strings stored in the outcome.
pub fn freeTrackOutcome(allocator: std.mem.Allocator, outcome: *TrackOutcome) void {
    for (outcome.tracked_paths.items) |path| allocator.free(path);
    outcome.tracked_paths.deinit();
}

// Tracks one file path and returns it as a single-path outcome.
fn trackSingleFile(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    absolute_path: []const u8,
) !TrackOutcome {
    _ = try store_api.track(allocator, omohi_dir, absolute_path);

    var outcome = TrackOutcome.init(allocator);
    errdefer freeTrackOutcome(allocator, &outcome);

    try outcome.tracked_paths.append(try allocator.dupe(u8, absolute_path));
    return outcome;
}

// Recursively tracks regular files below a directory and skips already tracked paths.
fn trackDirectory(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    absolute_path: []const u8,
) !TrackOutcome {
    var existing = try store_api.tracklist(allocator, omohi_dir);
    defer store_api.freeTracklist(allocator, &existing);

    var tracked_paths = std.StringHashMap(void).init(allocator);
    defer tracked_paths.deinit();
    for (existing.items) |entry| {
        try tracked_paths.put(entry.path.asSlice(), {});
    }

    var collected = std.array_list.Managed([]u8).init(allocator);
    defer {
        for (collected.items) |path| allocator.free(path);
        collected.deinit();
    }
    try collectTrackableFiles(allocator, absolute_path, &collected);
    std.mem.sort([]u8, collected.items, {}, lessThanPath);

    var outcome = TrackOutcome.init(allocator);
    errdefer freeTrackOutcome(allocator, &outcome);

    for (collected.items) |path| {
        if (tracked_paths.contains(path)) {
            outcome.skipped_paths += 1;
            continue;
        }

        _ = try store_api.track(allocator, omohi_dir, path);
        try tracked_paths.put(path, {});
        try outcome.tracked_paths.append(try allocator.dupe(u8, path));
    }

    return outcome;
}

// Recursively collects regular files below the absolute directory path.
fn collectTrackableFiles(
    allocator: std.mem.Allocator,
    absolute_dir_path: []const u8,
    collected: *std.array_list.Managed([]u8),
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
                try collectTrackableFiles(allocator, child_path, collected);
                allocator.free(child_path);
            },
            else => allocator.free(child_path),
        }
    }
}

// Sorts collected absolute paths in ascending byte order.
fn lessThanPath(_: void, lhs: []u8, rhs: []u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

test "ops track and tracklist round-trip" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    var outcome = try track(allocator, omohi_dir, "/tmp/ops-track.txt");
    defer freeTrackOutcome(allocator, &outcome);
    const version_bytes = try omohi_dir.readFileAlloc(allocator, "VERSION", 64);
    defer allocator.free(version_bytes);
    const actual_version = std.mem.trim(u8, std.mem.trimRight(u8, version_bytes, "\r\n"), " \t");
    try std.testing.expectEqualStrings("1", actual_version);

    var list = try tracklist(allocator, omohi_dir);
    defer freeTracklist(allocator, &list);

    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings("/tmp/ops-track.txt", outcome.tracked_paths.items[0]);
    try std.testing.expectEqualStrings("/tmp/ops-track.txt", list.items[0].path.asSlice());
}

test "ops untrack removes tracked entry and propagates NotFound" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    var outcome = try track(allocator, omohi_dir, "/tmp/ops-untrack.txt");
    defer freeTrackOutcome(allocator, &outcome);

    var list = try tracklist(allocator, omohi_dir);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try untrack(allocator, omohi_dir, list.items[0].id.asSlice());

    freeTracklist(allocator, &list);
    list = try tracklist(allocator, omohi_dir);
    defer freeTracklist(allocator, &list);
    try std.testing.expectEqual(@as(usize, 0), list.items.len);

    try std.testing.expectError(error.NotFound, untrack(allocator, omohi_dir, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"));
}

test "ops untrackMissing removes only missing tracked entries" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    {
        var file = try source_dir.createFile("missing.txt", .{});
        defer file.close();
        try file.writeAll("gone");
    }
    {
        var file = try source_dir.createFile("kept.txt", .{});
        defer file.close();
        try file.writeAll("stay");
    }

    const missing_path = try source_dir.realpathAlloc(allocator, "missing.txt");
    defer allocator.free(missing_path);
    const kept_path = try source_dir.realpathAlloc(allocator, "kept.txt");
    defer allocator.free(kept_path);

    try store_api.initializeVersionForFirstTrack(allocator, omohi_dir);
    _ = try store_api.track(allocator, omohi_dir, missing_path);
    _ = try store_api.track(allocator, omohi_dir, kept_path);
    try source_dir.deleteFile("missing.txt");

    var outcome = try untrackMissing(allocator, omohi_dir);
    defer freeUntrackMissingOutcome(allocator, &outcome);

    try std.testing.expectEqual(@as(usize, 1), outcome.untracked_paths.items.len);
    try std.testing.expectEqualStrings(missing_path, outcome.untracked_paths.items[0]);

    var list = try tracklist(allocator, omohi_dir);
    defer freeTracklist(allocator, &list);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings(kept_path, list.items[0].path.asSlice());
}

test "ops untrackMissing succeeds when there are no missing tracked entries" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    {
        var file = try source_dir.createFile("kept.txt", .{});
        defer file.close();
        try file.writeAll("stay");
    }

    const kept_path = try source_dir.realpathAlloc(allocator, "kept.txt");
    defer allocator.free(kept_path);

    try store_api.initializeVersionForFirstTrack(allocator, omohi_dir);
    _ = try store_api.track(allocator, omohi_dir, kept_path);

    var outcome = try untrackMissing(allocator, omohi_dir);
    defer freeUntrackMissingOutcome(allocator, &outcome);

    try std.testing.expectEqual(@as(usize, 0), outcome.untracked_paths.items.len);
}

test "track fails when VERSION is missing in non-empty store" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    var marker = try omohi_dir.createFile("HEAD", .{});
    defer marker.close();
    try marker.writeAll("dummy\n");

    try std.testing.expectError(
        error.MissingStoreVersion,
        track(allocator, omohi_dir, "/tmp/ops-track-missing-version.txt"),
    );
}

test "track expands directories recursively and skips duplicates" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

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

    const first_path = try source_dir.realpathAlloc(allocator, "a.txt");
    defer allocator.free(first_path);
    const root_path = try source_dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    var first = try track(allocator, omohi_dir, first_path);
    defer freeTrackOutcome(allocator, &first);

    var outcome = try track(allocator, omohi_dir, root_path);
    defer freeTrackOutcome(allocator, &outcome);

    try std.testing.expectEqual(@as(usize, 1), outcome.tracked_paths.items.len);
    try std.testing.expectEqual(@as(usize, 1), outcome.skipped_paths);
    try std.testing.expect(std.mem.endsWith(u8, outcome.tracked_paths.items[0], "/nested/b.txt"));
}
