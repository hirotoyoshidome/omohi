const std = @import("std");

const persistence_store = @import("./local/persistence.zig");
const ContentEntry = @import("./object/content_entry.zig").ContentEntry;
const hash = @import("./object/hash.zig");
const lock = @import("./storage/lock.zig");

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
