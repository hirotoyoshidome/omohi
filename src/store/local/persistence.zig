const staged_mod = @import("../storage/persistence/staged.zig");
const snapshot_mod = @import("../storage/persistence/snapshot.zig");
const commit_mod = @import("../storage/persistence/commit.zig");
const head_mod = @import("../storage/persistence/head.zig");
const layout = @import("../object/persistence_layout.zig");

pub const PersistenceLayout = layout.PersistenceLayout;

pub const EntryList = staged_mod.EntryList;
pub const loadStagedEntries = staged_mod.loadStagedEntries;
pub const freeEntries = staged_mod.freeEntries;
pub const moveObjectsFromStage = staged_mod.moveObjectsFromStage;
pub const resetStaged = staged_mod.resetStaged;

pub const writeSnapshot = snapshot_mod.writeSnapshot;

pub const writeCommit = commit_mod.writeCommit;

pub const writeHead = head_mod.writeHead;
