const std = @import("std");

const persistence_store = @import("./local/persistence.zig");
const ContentEntry = @import("./object/content_entry.zig").ContentEntry;
const hash = @import("./object/hash.zig");
const lock = @import("./storage/lock.zig");
const constrained_types = @import("./object/constrained_types.zig");

const max_add_file_size = 64 * 1024 * 1024;

/// Store facade API for ops layer.
/// The facade hides store internals (object/storage/local).
///
/// Planned public APIs (initial draft):
/// - initOmohiDirIfNeeded
/// - track, untrack
/// - add, rm
/// - commit
/// - status, tracklist
/// - find, show
/// - tagAdd, tagRemove, tagList
///
/// Adds a file into staging and writes both entry and staged object.
/// Memory: borrowed (allocator is only used for temporary allocations)
/// Errors: lock/I/O errors, error{FileTooLarge}, and constrained type errors.
pub fn add(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    source_dir: std.fs.Dir,
    source_path: []const u8,
) !void {
    try lock.acquireLock(omohi_dir);
    defer lock.releaseLock(omohi_dir);

    const persistence = persistence_store.PersistenceLayout.init(omohi_dir);
    try omohi_dir.makePath(persistence.stagedEntriesPath());
    try omohi_dir.makePath(persistence.stagedObjectsPath());

    const content_hash = try contentHashFromFile(allocator, source_dir, source_path);
    const entry_path = try std.fmt.allocPrint(
        allocator,
        "/objects/{s}/{s}",
        .{ content_hash[0..2], content_hash[0..] },
    );
    defer allocator.free(entry_path);

    const entry = ContentEntry{
        .path = try constrained_types.ContentPath.init(entry_path),
        .content_hash = try constrained_types.ContentHash.init(&content_hash),
    };
    const staged_file_id = hash.stagedFileIdFrom(source_path, &content_hash);

    try persistence_store.writeStagedEntry(allocator, persistence, &staged_file_id, entry);
    try persistence_store.copyFileToStagedObject(allocator, persistence, source_dir, source_path, &content_hash);
}

/// Registers an absolute file path under tracked/<TrackedFileId>.
/// Memory: borrowed (temporary allocations only)
/// Errors: error{AlreadyTracked} plus lock/I/O and constrained type errors.
pub fn track(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    absolute_path: []const u8,
) !constrained_types.TrackedFileId {
    try lock.acquireLock(omohi_dir);
    defer lock.releaseLock(omohi_dir);

    const persistence = persistence_store.PersistenceLayout.init(omohi_dir);
    try omohi_dir.makePath(persistence.trackedPath());
    try omohi_dir.makePath(persistence.trackedTrashPath());

    _ = try constrained_types.TrackedFilePath.init(absolute_path);

    var existing = try loadTrackedOrEmpty(allocator, persistence);
    defer if (existing) |*list| persistence_store.freeTrackedList(allocator, list);

    if (existing) |*list| {
        for (list.items) |entry| {
            if (std.mem.eql(u8, entry.path.asSlice(), absolute_path)) return error.AlreadyTracked;
        }
    }

    const tracked_id = constrained_types.TrackedFileId.generate();
    try persistence_store.writeTracked(allocator, persistence, tracked_id.asSlice(), absolute_path);
    return tracked_id;
}

/// Removes a tracked file by moving tracked/<id> into tracked/.trash/<id>.
/// Memory: borrowed
/// Errors: error{NotFound} plus lock/I/O and constrained type errors.
pub fn untrack(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    tracked_file_id: []const u8,
) !void {
    const id = try constrained_types.TrackedFileId.init(tracked_file_id);

    try lock.acquireLock(omohi_dir);
    defer lock.releaseLock(omohi_dir);

    const persistence = persistence_store.PersistenceLayout.init(omohi_dir);
    const tracked_path = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}",
        .{ persistence.trackedPath(), id.asSlice() },
    );
    defer allocator.free(tracked_path);

    var file = omohi_dir.openFile(tracked_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.NotFound,
        else => return err,
    };
    file.close();

    try persistence_store.deleteTracked(allocator, persistence, id.asSlice());
}

/// Loads current tracked entries from tracked/.
/// Memory: owned list, free with freeTracklist.
pub fn tracklist(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
) !persistence_store.TrackedList {
    const persistence = persistence_store.PersistenceLayout.init(omohi_dir);
    return (try loadTrackedOrEmpty(allocator, persistence)) orelse persistence_store.TrackedList.init(allocator);
}

pub fn freeTracklist(allocator: std.mem.Allocator, list: *persistence_store.TrackedList) void {
    persistence_store.freeTrackedList(allocator, list);
}

/// Executes the durable commit transaction: lock -> persist data -> HEAD -> cleanup.
/// Memory: borrowed (allocator used for temporary allocations only)
/// Errors: error{NothingToCommit}, underlying I/O or lock errors.
pub fn commit(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    message: []const u8,
) !void {
    try lock.acquireLock(omohi_dir);
    defer lock.releaseLock(omohi_dir);

    const persistence = persistence_store.PersistenceLayout.init(omohi_dir);

    var entries = try persistence_store.loadStagedEntries(allocator, persistence);
    defer persistence_store.freeEntries(allocator, &entries);

    if (entries.items.len == 0) return error.NothingToCommit;

    std.mem.sort(ContentEntry, entries.items, {}, lessThanPath);

    const snapshot_id = hash.snapshotIdFrom(entries.items);
    const commit_id = hash.commitIdFrom(snapshot_id[0..], message);

    try persistence_store.writeSnapshot(allocator, persistence, snapshot_id[0..], entries.items);
    try persistence_store.writeCommit(allocator, persistence, commit_id[0..], snapshot_id[0..], message);

    try persistence_store.moveObjectsFromStage(allocator, persistence);
    try persistence_store.writeHead(allocator, persistence, commit_id[0..]);
    try persistence_store.resetStaged(persistence);
}

fn lessThanPath(_: void, lhs: ContentEntry, rhs: ContentEntry) bool {
    return ContentEntry.lessThanByPath(lhs, rhs);
}

fn contentHashFromFile(
    allocator: std.mem.Allocator,
    source_dir: std.fs.Dir,
    source_path: []const u8,
) ![64]u8 {
    var source_file = try source_dir.openFile(source_path, .{});
    defer source_file.close();

    const stat = try source_file.stat();
    const file_size = std.math.cast(usize, stat.size) orelse return error.FileTooLarge;
    if (file_size > max_add_file_size) return error.FileTooLarge;
    const max_bytes = @max(file_size, @as(usize, 1));

    const bytes = try source_file.readToEndAlloc(allocator, max_bytes);
    defer allocator.free(bytes);

    return hash.sha256Hex(bytes);
}

fn loadTrackedOrEmpty(
    allocator: std.mem.Allocator,
    persistence: persistence_store.PersistenceLayout,
) !?persistence_store.TrackedList {
    return persistence_store.loadTracked(allocator, persistence) catch |err| switch (err) {
        error.MissingTracked => null,
        else => return err,
    };
}

test "track writes tracked entry and tracklist returns it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const tracked_id = try track(allocator, omohi_dir, "/tmp/tracked-a.txt");
    try std.testing.expectEqual(@as(usize, 32), tracked_id.asSlice().len);

    const tracked_path = try std.fmt.allocPrint(allocator, "tracked/{s}", .{tracked_id.asSlice()});
    defer allocator.free(tracked_path);
    const bytes = try omohi_dir.readFileAlloc(allocator, tracked_path, 256);
    defer allocator.free(bytes);
    try std.testing.expectEqualStrings("/tmp/tracked-a.txt", bytes);

    var list = try tracklist(allocator, omohi_dir);
    defer freeTracklist(allocator, &list);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings("/tmp/tracked-a.txt", list.items[0].path.asSlice());
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile("LOCK", .{}));
}

test "track rejects duplicate absolute path and releases lock" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    _ = try track(allocator, omohi_dir, "/tmp/same.txt");
    try std.testing.expectError(error.AlreadyTracked, track(allocator, omohi_dir, "/tmp/same.txt"));
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile("LOCK", .{}));
}

test "untrack moves tracked file into trash and missing id returns NotFound" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    const tracked_id = try track(allocator, omohi_dir, "/tmp/remove-me.txt");
    try untrack(allocator, omohi_dir, tracked_id.asSlice());

    const src_path = try std.fmt.allocPrint(allocator, "tracked/{s}", .{tracked_id.asSlice()});
    defer allocator.free(src_path);
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile(src_path, .{}));

    const trash_path = try std.fmt.allocPrint(allocator, "tracked/.trash/{s}", .{tracked_id.asSlice()});
    defer allocator.free(trash_path);
    const bytes = try omohi_dir.readFileAlloc(allocator, trash_path, 256);
    defer allocator.free(bytes);
    try std.testing.expectEqualStrings("/tmp/remove-me.txt", bytes);

    try std.testing.expectError(error.NotFound, untrack(allocator, omohi_dir, tracked_id.asSlice()));
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile("LOCK", .{}));
}

test "tracklist returns empty when tracked directory does not exist" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    var list = try tracklist(allocator, omohi_dir);
    defer freeTracklist(allocator, &list);
    try std.testing.expectEqual(@as(usize, 0), list.items.len);
}
