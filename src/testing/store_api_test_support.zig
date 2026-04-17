const std = @import("std");

const PersistenceLayout = @import("../store/object/persistence_layout.zig").PersistenceLayout;
const local_commit_tags = @import("../store/local/commit_tags.zig");

/// TEST-ONLY: Identifies an injected failure point within the commit transaction.
pub const CommitFailurePoint = enum {
    none,
    before_write_snapshot,
    before_write_commit,
    before_move_objects,
    before_write_head,
    before_reset_staged,
};

var commit_failure_point: CommitFailurePoint = .none;

/// TEST-ONLY: Fills a 64-byte id buffer with the requested byte.
pub fn filledHexId(ch: u8) [64]u8 {
    var value: [64]u8 = undefined;
    @memset(&value, ch);
    return value;
}

/// TEST-ONLY: Creates a file fixture for commit-related tests and returns its resolved absolute path.
pub fn addTestFileForCommit(
    root: std.fs.Dir,
    allocator: std.mem.Allocator,
    name: []const u8,
    contents: []const u8,
) ![]u8 {
    var file = try root.createFile(name, .{ .truncate = true });
    defer file.close();
    try file.writeAll(contents);
    return try root.realpathAlloc(allocator, name);
}

/// TEST-ONLY: Writes a commit fixture used by find-related tests.
pub fn writeFindFixtureCommit(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    commit_id: []const u8,
    message: []const u8,
    created_at: []const u8,
    is_empty: bool,
) !void {
    const persistence = PersistenceLayout.init(omohi_dir);
    const path = try persistence.commitsPath(allocator, commit_id);
    defer allocator.free(path);

    const snapshot_id = filledHexId('a');
    const content = try std.fmt.allocPrint(
        allocator,
        "snapshotId={s}\nmessage={s}\ncreatedAt={s}\nempty={s}\n",
        .{ snapshot_id[0..], message, created_at, if (is_empty) "true" else "false" },
    );
    defer allocator.free(content);

    const parent = std.fs.path.dirname(path) orelse return error.InvalidPath;
    try omohi_dir.makePath(parent);

    var file = try omohi_dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(content);
}

/// TEST-ONLY: Writes commit-tag fixtures used by find-related tests.
pub fn writeFindFixtureTags(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    commit_id: []const u8,
    tag_names: []const []const u8,
) !void {
    const persistence = PersistenceLayout.init(omohi_dir);
    try local_commit_tags.writeCommitTags(
        allocator,
        persistence,
        commit_id,
        tag_names,
        "2026-03-11T00:00:00.000Z",
        "2026-03-11T00:00:00.000Z",
    );
}

/// TEST-ONLY: Enables a specific injected commit failure point for recovery tests.
pub fn setCommitFailurePoint(point: CommitFailurePoint) void {
    commit_failure_point = point;
}

/// TEST-ONLY: Clears any injected commit failure point after a recovery test.
pub fn clearCommitFailurePoint() void {
    commit_failure_point = .none;
}

/// TEST-ONLY: Fails with `TestInjectedFailure` when the requested commit step is armed.
pub fn maybeFailCommitAt(point: CommitFailurePoint) !void {
    if (commit_failure_point == point) return error.TestInjectedFailure;
}

/// TEST-ONLY: Writes staged entry and object fixtures for commit-related tests.
pub fn writeCommitFixtureStage(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    path_suffix: []const u8,
    content_hash_ch: u8,
    payload: []const u8,
) !void {
    const persistence = PersistenceLayout.init(omohi_dir);
    try omohi_dir.makePath(persistence.stagedEntriesPath());
    try omohi_dir.makePath(persistence.stagedObjectsPath());

    const content_hash = filledHexId(content_hash_ch);
    const entry_text = try std.fmt.allocPrint(
        allocator,
        "path=/tmp/{s}.txt\ntrackedFileId=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\ncontentHash={s}\n",
        .{ path_suffix, content_hash[0..] },
    );
    defer allocator.free(entry_text);

    const entry_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.stagedEntriesPath(), path_suffix });
    defer allocator.free(entry_path);
    var entry_file = try omohi_dir.createFile(entry_path, .{});
    defer entry_file.close();
    try entry_file.writeAll(entry_text);

    const object_path = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}",
        .{ persistence.stagedObjectsPath(), content_hash[0..] },
    );
    defer allocator.free(object_path);
    var object_file = try omohi_dir.createFile(object_path, .{});
    defer object_file.close();
    try object_file.writeAll(payload);
}
