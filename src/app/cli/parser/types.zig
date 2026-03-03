pub const TrackArgs = struct {
    path: []const u8,
};

pub const UntrackArgs = struct {
    tracked_file_id: []const u8,
};

pub const AddArgs = struct {
    path: []const u8,
};

pub const RmArgs = struct {
    path: []const u8,
};

pub const CommitArgs = struct {
    message: []const u8,
    tags: []const []const u8,
    dry_run: bool,
};

pub const FindArgs = struct {
    tag: ?[]const u8,
    date: ?[]const u8,
};

pub const ShowArgs = struct {
    commit_id: []const u8,
};

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

pub const ParsedRequest = union(enum) {
    track: TrackArgs,
    untrack: UntrackArgs,
    add: AddArgs,
    rm: RmArgs,
    commit: CommitArgs,
    status,
    tracklist,
    find: FindArgs,
    show: ShowArgs,
    tag_ls: TagLsArgs,
    tag_add: TagAddArgs,
    tag_rm: TagRmArgs,
    help,
};

pub fn deinitParsedRequest(allocator: anytype, parsed: *ParsedRequest) void {
    switch (parsed.*) {
        .commit => |args| allocator.free(args.tags),
        else => {},
    }
}
