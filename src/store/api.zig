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
