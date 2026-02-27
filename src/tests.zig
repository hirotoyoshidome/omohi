// store tests
// objects
const _store_persistence_layout = @import("store/object/persistence_layout.zig");
const _store_constrained_types = @import("store/object/constrained_types.zig");
const _store_hash = @import("store/object/hash.zig");
// storage
const _store_atomic = @import("store/storage/atomic_write.zig");
const _store_lock = @import("store/storage/lock.zig");
const _store_time_utc = @import("store/storage/time/utc.zig");
// persistence
const _store_persistence_tracked = @import("store/storage/persistence/tracked.zig");
const _store_persistence_staged = @import("store/storage/persistence/staged.zig");
const _store_persistence_commit = @import("store/storage/persistence/commit.zig");
const _store_persistence_snapshot = @import("store/storage/persistence/snapshot.zig");
const _store_persistence_commit_tags = @import("store/storage/persistence/commit_tags.zig");
const _store_persistence_head = @import("store/storage/persistence/head.zig");
const _store_persistence_tags = @import("store/storage/persistence/tags.zig");
const _store_persistence_trash = @import("store/storage/persistence/trash.zig");
// local persistence
const _store_local_persistence = @import("store/local/persistence.zig");

// ops tests
const _ops_add = @import("ops/add_ops.zig");
const _ops_commit = @import("ops/commit_ops.zig");
const _ops_track = @import("ops/track_ops.zig");

test "load modules" {
    _ = _store_persistence_layout;
    _ = _store_constrained_types;
    _ = _store_hash;
    _ = _store_atomic;
    _ = _store_lock;
    _ = _store_time_utc;
    _ = _store_persistence_tracked;
    _ = _store_persistence_staged;
    _ = _store_persistence_commit;
    _ = _store_persistence_snapshot;
    _ = _store_persistence_commit_tags;
    _ = _store_persistence_head;
    _ = _store_persistence_tags;
    _ = _store_persistence_trash;
    _ = _store_local_persistence;
    _ = _ops_add;
    _ = _ops_commit;
    _ = _ops_track;
}
