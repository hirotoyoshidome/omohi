pub const OutputFormat = enum {
    text,
    json,
};

pub const TracklistField = enum {
    id,
    path,
};

pub const FindField = enum {
    commit_id,
    message,
    created_at,
};

pub const FindEmptyFilter = enum {
    all,
    empty_only,
    non_empty_only,
};

pub const ShowField = enum {
    commit_id,
    message,
    created_at,
    paths,
    tags,
};

pub const TrackArgs = struct {
    paths: []const []const u8,
};

pub const UntrackArgs = struct {
    tracked_file_id: ?[]const u8,
    missing: bool,
};

pub const AddArgs = struct {
    all: bool,
    paths: []const []const u8,
};

pub const RmArgs = struct {
    paths: []const []const u8,
};

pub const CommitArgs = struct {
    message: []const u8,
    tags: []const []const u8,
    dry_run: bool,
    empty: bool,
};

pub const TracklistArgs = struct {
    output: OutputFormat,
    fields: []const TracklistField,
};

pub const FindArgs = struct {
    tag: ?[]const u8,
    empty_filter: FindEmptyFilter,
    since: ?[]const u8,
    until: ?[]const u8,
    since_millis: ?i64,
    until_millis: ?i64,
    limit: ?usize,
    output: OutputFormat,
    fields: []const FindField,
};

pub const ShowArgs = struct {
    commit_id: []const u8,
    output: OutputFormat,
    fields: []const ShowField,
};

pub const JournalArgs = struct {};

pub const TagLsArgs = struct {
    commit_id: []const u8,
};

pub const TagAddArgs = struct {
    commit_id: []const u8,
    tag_names: []const []const u8,
};

pub const TagRmArgs = struct {
    commit_id: []const u8,
    tag_names: []const []const u8,
};

pub const HelpArgs = struct {
    topic: ?[]const u8,
};

pub const CompleteArgs = struct {
    index: usize,
    words: []const []const u8,
};

pub const ParsedRequest = union(enum) {
    track: TrackArgs,
    untrack: UntrackArgs,
    add: AddArgs,
    rm: RmArgs,
    commit: CommitArgs,
    status,
    tracklist: TracklistArgs,
    version,
    find: FindArgs,
    show: ShowArgs,
    journal: JournalArgs,
    tag_ls: TagLsArgs,
    tag_add: TagAddArgs,
    tag_rm: TagRmArgs,
    help: HelpArgs,
    complete: CompleteArgs,
};

// Releases any owned fields stored inside a parsed request union.
pub fn deinitParsedRequest(allocator: std.mem.Allocator, parsed: *ParsedRequest) void {
    switch (parsed.*) {
        .commit => |args| allocator.free(args.tags),
        .tracklist => |args| allocator.free(args.fields),
        .find => |args| allocator.free(args.fields),
        .show => |args| allocator.free(args.fields),
        else => {},
    }
}
const std = @import("std");
