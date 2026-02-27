const std = @import("std");

const ContentEntry = @import("./content_entry.zig").ContentEntry;
const constrained_types = @import("./constrained_types.zig");

pub const StatusKind = enum {
    untracked,
    tracked,
    changed,
    staged,
    committed,
};

pub const StatusEntry = struct {
    id: constrained_types.TrackedFileId,
    path: []u8,
    status: StatusKind,
};

pub const StatusList = std.array_list.Managed(StatusEntry);

pub const CommitSummary = struct {
    commit_id: constrained_types.CommitId,
    message: []u8,
    created_at: []u8,
};

pub const CommitSummaryList = std.array_list.Managed(CommitSummary);

pub const TagList = std.array_list.Managed([]u8);

pub const CommitDetails = struct {
    commit_id: constrained_types.CommitId,
    snapshot_id: constrained_types.SnapshotId,
    message: []u8,
    created_at: []u8,
    entries: std.array_list.Managed(ContentEntry),
    tags: TagList,
};
