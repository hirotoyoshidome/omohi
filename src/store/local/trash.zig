const std = @import("std");

const PersistenceLayout = @import("../object/persistence_layout.zig").PersistenceLayout;
const constrained_types = @import("../object/constrained_types.zig");

pub fn moveTrackedToTrash(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    tracked_file_id: []const u8,
) !void {
    _ = try constrained_types.TrackedFileId.init(tracked_file_id);
    const from_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.trackedPath(), tracked_file_id });
    defer allocator.free(from_path);
    const to_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.trackedTrashPath(), tracked_file_id });
    defer allocator.free(to_path);
    try moveFileToTrashPath(allocator, persistence.dir, from_path, to_path);
}

pub fn moveStagedEntryToTrash(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    staged_file_id: []const u8,
) !void {
    _ = try constrained_types.StagedFileId.init(staged_file_id);
    const from_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.stagedEntriesPath(), staged_file_id });
    defer allocator.free(from_path);
    const to_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.stagedEntriesTrashPath(), staged_file_id });
    defer allocator.free(to_path);
    try moveFileToTrashPath(allocator, persistence.dir, from_path, to_path);
}

pub fn moveStagedObjectToTrash(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    content_hash: []const u8,
) !void {
    _ = try constrained_types.ContentHash.init(content_hash);
    const from_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.stagedObjectsPath(), content_hash });
    defer allocator.free(from_path);
    const to_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.stagedObjectsTrashPath(), content_hash });
    defer allocator.free(to_path);
    try moveFileToTrashPath(allocator, persistence.dir, from_path, to_path);
}

pub fn moveTagToTrash(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    tag_name: []const u8,
) !void {
    validateTagFileName(tag_name) catch return error.InvalidTagName;
    const from_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.dataTagsPath(), tag_name });
    defer allocator.free(from_path);
    const to_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.dataTagsTrashPath(), tag_name });
    defer allocator.free(to_path);
    try moveFileToTrashPath(allocator, persistence.dir, from_path, to_path);
}

pub fn moveCommitTagsToTrash(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    commit_id: []const u8,
) !void {
    _ = try constrained_types.CommitId.init(commit_id);
    const from_path = try persistence.commitTagsPath(allocator, commit_id);
    defer allocator.free(from_path);
    const to_path = try persistence.commitTagsTrashPath(allocator, commit_id);
    defer allocator.free(to_path);
    try moveFileToTrashPath(allocator, persistence.dir, from_path, to_path);
}

pub fn moveFileToTrashPath(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    from_path: []const u8,
    to_path: []const u8,
) !void {
    _ = allocator;
    try ensureParentDirs(dir, to_path);

    var source_file = try dir.openFile(from_path, .{});
    defer source_file.close();
    try source_file.sync();

    try dir.rename(from_path, to_path);

    try syncParentDir(dir, from_path);
    try syncParentDir(dir, to_path);
}

fn ensureParentDirs(dir: std.fs.Dir, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| {
        if (parent.len == 0) return;
        try dir.makePath(parent);
    }
}

fn syncParentDir(dir: std.fs.Dir, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| {
        if (parent.len == 0) return try syncDir(dir);
        var parent_dir = try dir.openDir(parent, .{});
        defer parent_dir.close();
        try syncDir(parent_dir);
        return;
    }
    try syncDir(dir);
}

fn syncDir(dir: std.fs.Dir) !void {
    const rc = std.posix.system.fsync(dir.fd);
    switch (std.posix.errno(rc)) {
        .SUCCESS, .BADF, .INVAL, .ROFS => return,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}

fn validateTagFileName(name: []const u8) !void {
    _ = try constrained_types.TagName.init(name);
    if (std.mem.indexOfScalar(u8, name, '/')) |_| return error.InvalidTagName;
    if (std.mem.indexOf(u8, name, "..")) |_| return error.InvalidTagName;
}

test "moveTrackedToTrash relocates file under tracked .trash" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    var persistence = PersistenceLayout.init(omohi_dir);

    var tracked_id: [32]u8 = undefined;
    @memset(&tracked_id, 'a');
    const tracked_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.trackedPath(), &tracked_id });
    defer allocator.free(tracked_path);
    try ensureParentDirs(omohi_dir, tracked_path);
    var file = try omohi_dir.createFile(tracked_path, .{});
    try file.writeAll("/abs/path.txt");
    file.close();

    try moveTrackedToTrash(allocator, persistence, &tracked_id);

    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile(tracked_path, .{}));
    const trashed_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.trackedTrashPath(), &tracked_id });
    defer allocator.free(trashed_path);
    const bytes = try omohi_dir.readFileAlloc(allocator, trashed_path, 128);
    defer allocator.free(bytes);
    try std.testing.expectEqualStrings("/abs/path.txt", bytes);
}
