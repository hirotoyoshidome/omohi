pub const TrackArgs = struct {
    paths: []const []const u8,
};

pub const UntrackArgs = struct {
    tracked_file_id: []const u8,
};

pub const AddArgs = struct {
    paths: []const []const u8,
};

pub const RmArgs = struct {
    paths: []const []const u8,
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
    tracklist,
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
pub fn deinitParsedRequest(allocator: anytype, parsed: *ParsedRequest) void {
    switch (parsed.*) {
        .commit => |args| allocator.free(args.tags),
        else => {},
    }
}
