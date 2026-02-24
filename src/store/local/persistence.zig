const staged_mod = @import("../storage/persistence/staged.zig");
const tracked_mod = @import("../storage/persistence/tracked.zig");
const snapshot_mod = @import("../storage/persistence/snapshot.zig");
const commit_mod = @import("../storage/persistence/commit.zig");
const tags_mod = @import("../storage/persistence/tags.zig");
const commit_tags_mod = @import("../storage/persistence/commit_tags.zig");
const trash_mod = @import("../storage/persistence/trash.zig");
const head_mod = @import("../storage/persistence/head.zig");
const layout = @import("../object/persistence_layout.zig");

pub const PersistenceLayout = layout.PersistenceLayout;

pub const TrackedEntry = tracked_mod.TrackedEntry;
pub const TrackedList = tracked_mod.TrackedList;
pub const writeTracked = tracked_mod.writeTracked;
pub const deleteTracked = tracked_mod.deleteTracked;
pub const loadTracked = tracked_mod.loadTracked;
pub const freeTrackedList = tracked_mod.freeTrackedList;

pub const EntryList = staged_mod.EntryList;
pub const loadStagedEntries = staged_mod.loadStagedEntries;
pub const freeEntries = staged_mod.freeEntries;
pub const writeStagedEntry = staged_mod.writeStagedEntry;
pub const copyFileToStagedObject = staged_mod.copyFileToStagedObject;
pub const moveObjectsFromStage = staged_mod.moveObjectsFromStage;
pub const resetStaged = staged_mod.resetStaged;

pub const writeSnapshot = snapshot_mod.writeSnapshot;

pub const writeCommit = commit_mod.writeCommit;

pub const writeTag = tags_mod.writeTag;
pub const readTagCreatedAt = tags_mod.readTagCreatedAt;
pub const deleteTag = tags_mod.deleteTag;

pub const CommitTagsRecord = commit_tags_mod.CommitTagsRecord;
pub const writeCommitTags = commit_tags_mod.writeCommitTags;
pub const readCommitTags = commit_tags_mod.readCommitTags;
pub const deleteCommitTags = commit_tags_mod.deleteCommitTags;

pub const moveTrackedToTrash = trash_mod.moveTrackedToTrash;
pub const moveStagedEntryToTrash = trash_mod.moveStagedEntryToTrash;
pub const moveStagedObjectToTrash = trash_mod.moveStagedObjectToTrash;
pub const moveTagToTrash = trash_mod.moveTagToTrash;
pub const moveCommitTagsToTrash = trash_mod.moveCommitTagsToTrash;

pub const writeHead = head_mod.writeHead;
