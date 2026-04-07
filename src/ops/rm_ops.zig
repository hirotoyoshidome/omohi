const std = @import("std");

const store_api = @import("../store/api.zig");
pub const RmOutcome = store_api.RmBatchOutcome;

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
    store_api.freeRmBatchOutcome(allocator, outcome);
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
    return store_api.rmTree(allocator, omohi_dir, absolute_path);
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
