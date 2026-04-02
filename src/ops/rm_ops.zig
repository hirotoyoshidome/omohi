const std = @import("std");

const store_api = @import("../store/api.zig");
const status_ops = @import("./status_ops.zig");

pub const RmOutcome = struct {
    unstaged_paths: std.array_list.Managed([]u8),
    skipped_untracked: usize,
    skipped_not_staged: usize,
    skipped_non_regular: usize,

    // Initializes an empty rm outcome that owns its collected unstaged paths.
    pub fn init(allocator: std.mem.Allocator) RmOutcome {
        return .{
            .unstaged_paths = std.array_list.Managed([]u8).init(allocator),
            .skipped_untracked = 0,
            .skipped_not_staged = 0,
            .skipped_non_regular = 0,
        };
    }
};

/// Removes a staged file entry from staging by source path.
pub fn rm(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    absolute_path: []const u8,
) !RmOutcome {
    try store_api.ensureStoreVersion(allocator, omohi_dir);

    var dir = std.fs.openDirAbsolute(absolute_path, .{ .iterate = true, .access_sub_paths = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return rmSingleFile(allocator, omohi_dir, absolute_path),
        else => return err,
    };
    defer dir.close();

    return rmDirectory(allocator, omohi_dir, absolute_path);
}

// Releases all owned unstaged path strings stored in the outcome.
pub fn freeRmOutcome(allocator: std.mem.Allocator, outcome: *RmOutcome) void {
    for (outcome.unstaged_paths.items) |path| allocator.free(path);
    outcome.unstaged_paths.deinit();
}

// Unstages one tracked file and returns a single-path outcome.
fn rmSingleFile(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    absolute_path: []const u8,
) !RmOutcome {
    try store_api.rm(allocator, omohi_dir, absolute_path);

    var outcome = RmOutcome.init(allocator);
    errdefer freeRmOutcome(allocator, &outcome);
    try outcome.unstaged_paths.append(try allocator.dupe(u8, absolute_path));
    return outcome;
}

// Unstages every staged regular file below the directory and records skip counts.
fn rmDirectory(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    absolute_path: []const u8,
) !RmOutcome {
    var outcome = RmOutcome.init(allocator);
    errdefer freeRmOutcome(allocator, &outcome);

    var tracked_statuses = try status_ops.status(allocator, omohi_dir);
    defer status_ops.freeStatusList(allocator, &tracked_statuses);

    var tracked_paths = std.StringHashMap(void).init(allocator);
    defer tracked_paths.deinit();
    var staged_paths = std.StringHashMap(void).init(allocator);
    defer staged_paths.deinit();
    for (tracked_statuses.items) |entry| {
        try tracked_paths.put(entry.path, {});
        if (entry.status == .staged) try staged_paths.put(entry.path, {});
    }

    var collected = std.array_list.Managed([]u8).init(allocator);
    defer {
        for (collected.items) |path| allocator.free(path);
        collected.deinit();
    }
    try collectRegularFiles(allocator, absolute_path, &collected, &outcome.skipped_non_regular);
    std.mem.sort([]u8, collected.items, {}, lessThanPath);

    for (collected.items) |path| {
        if (!tracked_paths.contains(path)) {
            outcome.skipped_untracked += 1;
            continue;
        }
        if (!staged_paths.contains(path)) {
            outcome.skipped_not_staged += 1;
            continue;
        }

        try store_api.rm(allocator, omohi_dir, path);
        try outcome.unstaged_paths.append(try allocator.dupe(u8, path));
    }

    return outcome;
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

test "rm removes staged entry for tracked file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try store_api.initializeVersionForFirstTrack(allocator, omohi_dir);

    var file = try source_dir.createFile("memo.txt", .{});
    try file.writeAll("hello");
    file.close();

    const absolute_path = try source_dir.realpathAlloc(allocator, "memo.txt");
    defer allocator.free(absolute_path);

    _ = try store_api.track(allocator, omohi_dir, absolute_path);
    try store_api.add(allocator, omohi_dir, absolute_path);
    var outcome = try rm(allocator, omohi_dir, absolute_path);
    defer freeRmOutcome(allocator, &outcome);

    var entries = try omohi_dir.openDir("staged/entries", .{ .iterate = true });
    defer entries.close();
    var it = entries.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .file) return error.ExpectedNoStagedEntryFiles;
    }
}

test "rm propagates staged-not-found for tracked but unstaged path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try store_api.initializeVersionForFirstTrack(allocator, omohi_dir);

    var file = try source_dir.createFile("memo.txt", .{});
    try file.writeAll("hello");
    file.close();

    const absolute_path = try source_dir.realpathAlloc(allocator, "memo.txt");
    defer allocator.free(absolute_path);
    _ = try store_api.track(allocator, omohi_dir, absolute_path);

    try std.testing.expectError(error.StagedFileNotFound, rm(allocator, omohi_dir, absolute_path));
}

test "rm removes staged files recursively and skips non-staged files under directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try store_api.initializeVersionForFirstTrack(allocator, omohi_dir);

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

    _ = try store_api.track(allocator, omohi_dir, a_path);
    _ = try store_api.track(allocator, omohi_dir, b_path);
    try store_api.add(allocator, omohi_dir, a_path);

    var outcome = try rm(allocator, omohi_dir, root_path);
    defer freeRmOutcome(allocator, &outcome);

    try std.testing.expectEqual(@as(usize, 1), outcome.unstaged_paths.items.len);
    try std.testing.expectEqual(@as(usize, 1), outcome.skipped_not_staged);
    try std.testing.expectEqual(@as(usize, 1), outcome.skipped_untracked);
}
