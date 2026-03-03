pub const CommandSpec = struct {
    name: []const u8,
    usage: []const u8,
};

pub const all = [_]CommandSpec{
    .{ .name = "track", .usage = "track <path>" },
    .{ .name = "untrack", .usage = "untrack <trackedFileId>" },
    .{ .name = "add", .usage = "add <path>" },
    .{ .name = "rm", .usage = "rm <path>" },
    .{ .name = "commit", .usage = "commit -m <message> [-t <tag>] [--dry-run]" },
    .{ .name = "status", .usage = "status" },
    .{ .name = "tracklist", .usage = "tracklist" },
    .{ .name = "find", .usage = "find [--tag <tag>] [--date YYYY-MM-DD]" },
    .{ .name = "show", .usage = "show <commitId>" },
    .{ .name = "tag ls", .usage = "tag ls <commitId>" },
    .{ .name = "tag add", .usage = "tag add <commitId> <tagNames...>" },
    .{ .name = "tag rm", .usage = "tag rm <commitId> <tagNames...>" },
    .{ .name = "help", .usage = "help" },
};
