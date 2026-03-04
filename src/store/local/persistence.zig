const staged_mod = @import("../storage/persistence/staged.zig");
const tracked_mod = @import("../storage/persistence/tracked.zig");
const snapshot_mod = @import("../storage/persistence/snapshot.zig");
const commit_mod = @import("../storage/persistence/commit.zig");
const tags_mod = @import("../storage/persistence/tags.zig");
const commit_tags_mod = @import("../storage/persistence/commit_tags.zig");
const trash_mod = @import("../storage/persistence/trash.zig");
const head_mod = @import("../storage/persistence/head.zig");
const version_mod = @import("../storage/persistence/version.zig");
const layout = @import("../object/persistence_layout.zig");

pub const PersistenceLayout = layout.PersistenceLayout;

pub const TrackedEntry = tracked_mod.TrackedEntry;
pub const TrackedList = tracked_mod.TrackedList;
pub const write_tracked = tracked_mod.writeTracked;
pub const delete_tracked = tracked_mod.deleteTracked;
pub const load_tracked = tracked_mod.loadTracked;
pub const free_tracked_list = tracked_mod.freeTrackedList;

pub const EntryList = staged_mod.EntryList;
pub const load_staged_entries = staged_mod.loadStagedEntries;
pub const free_entries = staged_mod.freeEntries;
pub const write_staged_entry = staged_mod.writeStagedEntry;
pub const copy_file_to_staged_object = staged_mod.copyFileToStagedObject;
pub const move_objects_from_stage = staged_mod.moveObjectsFromStage;
pub const reset_staged = staged_mod.resetStaged;

pub const write_snapshot = snapshot_mod.writeSnapshot;

pub const write_commit = commit_mod.writeCommit;

pub const write_tag = tags_mod.writeTag;
pub const read_tag_created_at = tags_mod.readTagCreatedAt;
pub const delete_tag = tags_mod.deleteTag;

pub const CommitTagsRecord = commit_tags_mod.CommitTagsRecord;
pub const write_commit_tags = commit_tags_mod.writeCommitTags;
pub const read_commit_tags = commit_tags_mod.readCommitTags;
pub const delete_commit_tags = commit_tags_mod.deleteCommitTags;

pub const move_tracked_to_trash = trash_mod.moveTrackedToTrash;
pub const move_staged_entry_to_trash = trash_mod.moveStagedEntryToTrash;
pub const move_staged_object_to_trash = trash_mod.moveStagedObjectToTrash;
pub const move_tag_to_trash = trash_mod.moveTagToTrash;
pub const move_commit_tags_to_trash = trash_mod.moveCommitTagsToTrash;

pub const write_head = head_mod.writeHead;

pub const write_version = version_mod.writeVersion;
pub const read_version = version_mod.readVersion;
pub const ensure_version = version_mod.ensureVersion;
