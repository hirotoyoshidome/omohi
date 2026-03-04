// store tests
// objects
const _store_persistence_layout = @import("store/object/persistence_layout.zig");
const _store_constrained_types = @import("store/object/constrained_types.zig");
const _store_hash = @import("store/object/hash.zig");
// storage
const _store_atomic = @import("store/storage/atomic_write.zig");
const _store_lock = @import("store/storage/lock.zig");
const _store_time_utc = @import("store/storage/time/utc.zig");
const _store_version_guard = @import("store/storage/version_guard.zig");
// local
const _store_local_tracked = @import("store/local/tracked.zig");
const _store_local_staged = @import("store/local/staged.zig");
const _store_local_commit = @import("store/local/commit.zig");
const _store_local_snapshot = @import("store/local/snapshot.zig");
const _store_local_commit_tags = @import("store/local/commit_tags.zig");
const _store_local_head = @import("store/local/head.zig");
const _store_local_tags = @import("store/local/tags.zig");
const _store_local_trash = @import("store/local/trash.zig");
const _store_local_version = @import("store/local/version.zig");

// ops tests
const _ops_track = @import("ops/track_ops.zig");
const _ops_add = @import("ops/add_ops.zig");
const _ops_rm = @import("ops/rm_ops.zig");
const _ops_commit = @import("ops/commit_ops.zig");
const _ops_status = @import("ops/status_ops.zig");
const _ops_find = @import("ops/find_ops.zig");
const _ops_show = @import("ops/show_ops.zig");
const _ops_tag = @import("ops/tag_ops.zig");

// app/cli tests
const _app_cli_run = @import("app/cli/run.zig");
const _app_cli_error_map = @import("app/cli/error/error_map.zig");
const _app_cli_error_message = @import("app/cli/error/error_message.zig");
const _app_cli_parser = @import("app/cli/parser/parse.zig");
const _app_cli_dispatch = @import("app/cli/runtime/dispatch.zig");

test "load modules" {
    _ = _store_persistence_layout;
    _ = _store_constrained_types;
    _ = _store_hash;
    _ = _store_atomic;
    _ = _store_lock;
    _ = _store_time_utc;
    _ = _store_version_guard;
    _ = _store_local_tracked;
    _ = _store_local_staged;
    _ = _store_local_commit;
    _ = _store_local_snapshot;
    _ = _store_local_commit_tags;
    _ = _store_local_head;
    _ = _store_local_tags;
    _ = _store_local_trash;
    _ = _store_local_version;
    _ = _ops_track;
    _ = _ops_add;
    _ = _ops_rm;
    _ = _ops_commit;
    _ = _ops_status;
    _ = _ops_find;
    _ = _ops_show;
    _ = _ops_tag;
    _ = _app_cli_run;
    _ = _app_cli_error_map;
    _ = _app_cli_error_message;
    _ = _app_cli_parser;
    _ = _app_cli_dispatch;
}
