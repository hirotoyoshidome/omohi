// store tests
// objects
const _store_persistence_layout = @import("store/object/persistence_layout.zig");
const _store_constrained_types = @import("store/object/constrained_types.zig");
const _store_hash = @import("store/object/hash.zig");
// storage
const _store_atomic = @import("store/storage/atomic_write.zig");
const _store_lock = @import("store/storage/lock.zig");
const _store_time_utc = @import("store/storage/time/utc.zig");
const _store_time_local_timestamp = @import("store/storage/time/local_timestamp.zig");
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
const _store_local_journal = @import("store/local/journal.zig");

// ops tests
const _ops_track = @import("ops/track_ops.zig");
const _ops_add = @import("ops/add_ops.zig");
const _ops_rm = @import("ops/rm_ops.zig");
const _ops_commit = @import("ops/commit_ops.zig");
const _ops_status = @import("ops/status_ops.zig");
const _ops_find = @import("ops/find_ops.zig");
const _ops_show = @import("ops/show_ops.zig");
const _ops_tag = @import("ops/tag_ops.zig");
const _ops_completion = @import("ops/completion_ops.zig");
const _ops_journal_append = @import("ops/journal/append.zig");
const _ops_journal = @import("ops/journal_ops.zig");

// app/cli tests
const _app_cli_run = @import("app/cli/run.zig");
const _app_cli_error_map = @import("app/cli/error/error_map.zig");
const _app_cli_error_message = @import("app/cli/error/error_message.zig");
const _app_cli_parser = @import("app/cli/parser/parse.zig");
const _app_cli_dispatch = @import("app/cli/runtime/dispatch.zig");
const _app_cli_journal_adapter = @import("app/cli/runtime/journal_adapter.zig");
const _app_cli_pager = @import("app/cli/runtime/pager.zig");
const _app_cli_terminal_color = @import("app/cli/runtime/terminal_color.zig");
const _app_cli_ansi_color = @import("app/cli/presenter/ansi_color.zig");
const _app_cli_output = @import("app/cli/presenter/output.zig");
const _app_cli_version = @import("app/cli/command/version.zig");
const _app_cli_journal = @import("app/cli/command/journal.zig");
const _app_cli_command_catalog = @import("app/cli/command_catalog.zig");
const _app_cli_docs_render_markdown = @import("app/cli/docs/render_markdown.zig");
const _app_cli_docs_render_man = @import("app/cli/docs/render_man.zig");

test "load modules" {
    _ = _store_persistence_layout;
    _ = _store_constrained_types;
    _ = _store_hash;
    _ = _store_atomic;
    _ = _store_lock;
    _ = _store_time_utc;
    _ = _store_time_local_timestamp;
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
    _ = _store_local_journal;
    _ = _ops_track;
    _ = _ops_add;
    _ = _ops_rm;
    _ = _ops_commit;
    _ = _ops_status;
    _ = _ops_find;
    _ = _ops_show;
    _ = _ops_tag;
    _ = _ops_completion;
    _ = _ops_journal_append;
    _ = _ops_journal;
    _ = _app_cli_run;
    _ = _app_cli_error_map;
    _ = _app_cli_error_message;
    _ = _app_cli_parser;
    _ = _app_cli_dispatch;
    _ = _app_cli_journal_adapter;
    _ = _app_cli_pager;
    _ = _app_cli_terminal_color;
    _ = _app_cli_ansi_color;
    _ = _app_cli_output;
    _ = _app_cli_version;
    _ = _app_cli_journal;
    _ = _app_cli_command_catalog;
    _ = _app_cli_docs_render_markdown;
    _ = _app_cli_docs_render_man;
}
