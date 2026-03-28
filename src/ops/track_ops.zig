const std = @import("std");

const store_api = @import("../store/api.zig");

pub const TrackedList = store_api.TrackedList;
pub const TrackOutcome = struct {
    tracked_paths: std.array_list.Managed([]u8),
    skipped_paths: usize,

    pub fn init(allocator: std.mem.Allocator) TrackOutcome {
        return .{
            .tracked_paths = std.array_list.Managed([]u8).init(allocator),
            .skipped_paths = 0,
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

/// Returns tracked id/path records.
pub fn tracklist(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
) !TrackedList {
    try store_api.ensureStoreVersion(allocator, omohi_dir);
    return store_api.tracklist(allocator, omohi_dir);
}

pub fn freeTracklist(allocator: std.mem.Allocator, list: *TrackedList) void {
    store_api.freeTracklist(allocator, list);
}

pub fn freeTrackOutcome(allocator: std.mem.Allocator, outcome: *TrackOutcome) void {
    for (outcome.tracked_paths.items) |path| allocator.free(path);
    outcome.tracked_paths.deinit();
}

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
