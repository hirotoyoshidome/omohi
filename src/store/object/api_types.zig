const std = @import("std");

const ContentEntry = @import("./content_entry.zig").ContentEntry;
const constrained_types = @import("./constrained_types.zig");

pub const StatusKind = enum {
    untracked,
    tracked,
    changed,
    missing,
    staged,
    committed,
};

pub const StatusEntry = struct {
    id: constrained_types.TrackedFileId,
    path: []u8,
    status: StatusKind,
};

pub const StatusList = std.array_list.Managed(StatusEntry);

pub const AddBatchOutcome = struct {
    staged_paths: std.array_list.Managed([]u8),
    skipped_untracked: usize,
    skipped_missing: usize,
    skipped_non_regular: usize,
    skipped_already_staged: usize,
    skipped_no_change: usize,

    // Initializes an empty add batch outcome that owns collected staged paths.
    pub fn init(allocator: std.mem.Allocator) AddBatchOutcome {
        return .{
            .staged_paths = std.array_list.Managed([]u8).init(allocator),
            .skipped_untracked = 0,
            .skipped_missing = 0,
            .skipped_non_regular = 0,
            .skipped_already_staged = 0,
            .skipped_no_change = 0,
        };
    }
};

pub const RmBatchOutcome = struct {
    unstaged_paths: std.array_list.Managed([]u8),
    skipped_untracked: usize,
    skipped_not_staged: usize,
    skipped_non_regular: usize,

    // Initializes an empty rm batch outcome that owns collected unstaged paths.
    pub fn init(allocator: std.mem.Allocator) RmBatchOutcome {
        return .{
            .unstaged_paths = std.array_list.Managed([]u8).init(allocator),
            .skipped_untracked = 0,
            .skipped_not_staged = 0,
            .skipped_non_regular = 0,
        };
    }
};

pub const CommitSummary = struct {
    commit_id: constrained_types.CommitId,
    message: []u8,
    created_at: []u8,
    local_created_at: []u8,
};

pub const CommitSummaryList = std.array_list.Managed(CommitSummary);

pub const StringList = std.array_list.Managed([]u8);
pub const TagList = StringList;

pub const CommitDetails = struct {
    commit_id: constrained_types.CommitId,
    snapshot_id: constrained_types.SnapshotId,
    message: []u8,
    created_at: []u8,
    entries: std.array_list.Managed(ContentEntry),
    tags: TagList,
};
