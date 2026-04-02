const std = @import("std");

const store_api = @import("../store/api.zig");

pub const CandidateList = std.array_list.Managed([]u8);

const top_level_commands = [_][]const u8{
    "track", "untrack", "add", "rm", "commit", "status", "tracklist", "version", "find", "show", "journal", "tag", "help",
};
const top_level_aliases = [_][]const u8{ "-h", "--help", "-v", "--version" };
const tag_commands = [_][]const u8{ "ls", "add", "rm" };
const commit_options = [_][]const u8{ "-m", "--message", "-t", "--tag", "--dry-run" };
const find_options = [_][]const u8{ "-t", "--tag", "-d", "--date" };
const help_topics = [_][]const u8{ "track", "untrack", "add", "rm", "commit", "status", "tracklist", "version", "find", "show", "journal", "tag", "help" };

// Reports whether completion at the current cursor position needs store-backed data.
pub fn requiresStore(words: []const []const u8, index: usize) bool {
    if (words.len == 0 or index >= words.len) return false;
    if (index == 1) return false;

    const command = words[1];
    if (std.mem.eql(u8, command, "untrack")) return index == 2;
    if (std.mem.eql(u8, command, "show")) return index == 2;
    if (std.mem.eql(u8, command, "rm")) return index == 2;
    if (std.mem.eql(u8, command, "find")) return expectsValue(words, index, "--tag", "-t");
    if (std.mem.eql(u8, command, "commit")) return expectsValue(words, index, "--tag", "-t");

    if (std.mem.eql(u8, command, "tag")) {
        if (index < 2) return false;
        if (index == 2) return false;
        if (words.len < 3) return false;
        const subcommand = words[2];
        if (std.mem.eql(u8, subcommand, "ls")) return index == 3;
        if (std.mem.eql(u8, subcommand, "add")) return index >= 3;
        if (std.mem.eql(u8, subcommand, "rm")) return index >= 3;
    }

    return false;
}

// Completes command words into an owned candidate list that callers must free.
pub fn complete(
    allocator: std.mem.Allocator,
    maybe_omohi_dir: ?std.fs.Dir,
    words: []const []const u8,
    index: usize,
) !CandidateList {
    var out = CandidateList.init(allocator);
    errdefer freeCandidateList(allocator, &out);

    if (words.len == 0 or index >= words.len) return out;

    const current = words[index];
    if (index == 1) {
        try appendFilteredStatic(allocator, &out, &top_level_commands, current);
        try appendFilteredStatic(allocator, &out, &top_level_aliases, current);
        return out;
    }

    const command = words[1];
    if (std.mem.eql(u8, command, "tag")) {
        try completeTagCommand(allocator, &out, maybe_omohi_dir, words, index, current);
        return out;
    }
    if (std.mem.eql(u8, command, "commit")) {
        try completeCommitCommand(allocator, &out, maybe_omohi_dir, words, index, current);
        return out;
    }
    if (std.mem.eql(u8, command, "find")) {
        if (expectsValue(words, index, "--tag", "-t")) {
            if (maybe_omohi_dir) |omohi_dir| {
                var tags = try loadTagNames(allocator, omohi_dir);
                defer freeCandidateList(allocator, &tags);
                try appendFilteredOwned(allocator, &out, tags.items, current);
            }
            return out;
        }
        try appendFilteredStatic(allocator, &out, &find_options, current);
        return out;
    }
    if (std.mem.eql(u8, command, "help")) {
        try appendFilteredStatic(allocator, &out, &help_topics, current);
        return out;
    }
    if (std.mem.eql(u8, command, "untrack") and index == 2) {
        if (maybe_omohi_dir) |omohi_dir| {
            var ids = try loadTrackedFileIds(allocator, omohi_dir);
            defer freeCandidateList(allocator, &ids);
            try appendFilteredOwned(allocator, &out, ids.items, current);
        }
        return out;
    }
    if (std.mem.eql(u8, command, "show") and index == 2) {
        if (maybe_omohi_dir) |omohi_dir| {
            var ids = try loadCommitIds(allocator, omohi_dir);
            defer freeCandidateList(allocator, &ids);
            try appendFilteredOwned(allocator, &out, ids.items, current);
        }
        return out;
    }
    if (std.mem.eql(u8, command, "rm") and index == 2) {
        if (maybe_omohi_dir) |omohi_dir| {
            var paths = try loadStagedPaths(allocator, omohi_dir);
            defer freeCandidateList(allocator, &paths);
            try appendFilteredOwned(allocator, &out, paths.items, current);
        }
        return out;
    }

    return out;
}

// Releases all owned completion candidate strings.
pub fn freeCandidateList(allocator: std.mem.Allocator, list: *CandidateList) void {
    for (list.items) |item| allocator.free(item);
    list.deinit();
}

// Completes `tag` subcommands, commit ids, and tag names.
fn completeTagCommand(
    allocator: std.mem.Allocator,
    out: *CandidateList,
    maybe_omohi_dir: ?std.fs.Dir,
    words: []const []const u8,
    index: usize,
    current: []const u8,
) !void {
    if (index == 2) {
        try appendFilteredStatic(allocator, out, &tag_commands, current);
        return;
    }
    if (words.len < 3) return;

    const subcommand = words[2];
    if (index == 3) {
        if ((std.mem.eql(u8, subcommand, "ls") or std.mem.eql(u8, subcommand, "add") or std.mem.eql(u8, subcommand, "rm")) and maybe_omohi_dir != null) {
            var ids = try loadCommitIds(allocator, maybe_omohi_dir.?);
            defer freeCandidateList(allocator, &ids);
            try appendFilteredOwned(allocator, out, ids.items, current);
        }
        return;
    }

    if (maybe_omohi_dir == null) return;
    if (std.mem.eql(u8, subcommand, "add")) {
        var tags = try loadTagNames(allocator, maybe_omohi_dir.?);
        defer freeCandidateList(allocator, &tags);
        try appendFilteredOwned(allocator, out, tags.items, current);
        return;
    }
    if (std.mem.eql(u8, subcommand, "rm")) {
        var tags = try loadCommitTags(allocator, maybe_omohi_dir.?, words[3]);
        defer freeCandidateList(allocator, &tags);
        try appendFilteredOwned(allocator, out, tags.items, current);
    }
}

// Completes commit options and tag values for the `commit` command.
fn completeCommitCommand(
    allocator: std.mem.Allocator,
    out: *CandidateList,
    maybe_omohi_dir: ?std.fs.Dir,
    words: []const []const u8,
    index: usize,
    current: []const u8,
) !void {
    if (expectsValue(words, index, "--message", "-m")) return;

    if (expectsValue(words, index, "--tag", "-t")) {
        if (maybe_omohi_dir) |omohi_dir| {
            var tags = try loadTagNames(allocator, omohi_dir);
            defer freeCandidateList(allocator, &tags);
            try appendFilteredOwned(allocator, out, tags.items, current);
        }
        return;
    }

    try appendFilteredStatic(allocator, out, &commit_options, current);
}

// Loads tracked file ids into an owned candidate list sorted ascending.
fn loadTrackedFileIds(allocator: std.mem.Allocator, omohi_dir: std.fs.Dir) !CandidateList {
    try store_api.ensureStoreVersion(allocator, omohi_dir);
    var tracked = try store_api.tracklist(allocator, omohi_dir);
    defer store_api.freeTracklist(allocator, &tracked);

    var out = CandidateList.init(allocator);
    errdefer freeCandidateList(allocator, &out);

    for (tracked.items) |entry| {
        try out.append(try allocator.dupe(u8, entry.id.asSlice()));
    }
    std.mem.sort([]u8, out.items, {}, isStringAscLessThan);
    return out;
}

// Loads commit ids into an owned candidate list.
fn loadCommitIds(allocator: std.mem.Allocator, omohi_dir: std.fs.Dir) !CandidateList {
    try store_api.ensureStoreVersion(allocator, omohi_dir);
    var ids = try store_api.commitIdList(allocator, omohi_dir);
    defer store_api.freeStringList(allocator, &ids);
    return try dupList(allocator, ids.items);
}

// Loads all known tag names into an owned candidate list.
fn loadTagNames(allocator: std.mem.Allocator, omohi_dir: std.fs.Dir) !CandidateList {
    try store_api.ensureStoreVersion(allocator, omohi_dir);
    var tags = try store_api.tagNameList(allocator, omohi_dir);
    defer store_api.freeStringList(allocator, &tags);
    return try dupList(allocator, tags.items);
}

// Loads tags for one commit into an owned candidate list sorted ascending.
fn loadCommitTags(allocator: std.mem.Allocator, omohi_dir: std.fs.Dir, commit_id: []const u8) !CandidateList {
    try store_api.ensureStoreVersion(allocator, omohi_dir);
    var tags = try store_api.tagList(allocator, omohi_dir, commit_id);
    defer store_api.freeTagList(allocator, &tags);

    const out = try dupList(allocator, tags.items);
    std.mem.sort([]u8, out.items, {}, isStringAscLessThan);
    return out;
}

// Loads staged paths into an owned candidate list.
fn loadStagedPaths(allocator: std.mem.Allocator, omohi_dir: std.fs.Dir) !CandidateList {
    try store_api.ensureStoreVersion(allocator, omohi_dir);
    var paths = try store_api.stagedPathList(allocator, omohi_dir);
    defer store_api.freeStringList(allocator, &paths);
    return try dupList(allocator, paths.items);
}

// Duplicates candidate strings into owned storage for the caller to free.
fn dupList(allocator: std.mem.Allocator, items: []const []u8) !CandidateList {
    var out = CandidateList.init(allocator);
    errdefer freeCandidateList(allocator, &out);

    for (items) |item| try out.append(try allocator.dupe(u8, item));
    return out;
}

// Appends static completion items that match the current prefix.
fn appendFilteredStatic(
    allocator: std.mem.Allocator,
    out: *CandidateList,
    items: []const []const u8,
    prefix: []const u8,
) !void {
    for (items) |item| {
        if (std.mem.startsWith(u8, item, prefix)) {
            try out.append(try allocator.dupe(u8, item));
        }
    }
}

// Appends owned completion items that match the current prefix.
fn appendFilteredOwned(
    allocator: std.mem.Allocator,
    out: *CandidateList,
    items: []const []u8,
    prefix: []const u8,
) !void {
    for (items) |item| {
        if (std.mem.startsWith(u8, item, prefix)) {
            try out.append(try allocator.dupe(u8, item));
        }
    }
}

// Reports whether the current cursor position is the value for the given option spellings.
fn expectsValue(words: []const []const u8, index: usize, long: []const u8, short: []const u8) bool {
    if (index == 0 or index >= words.len) return false;
    const prev = words[index - 1];
    return std.mem.eql(u8, prev, long) or std.mem.eql(u8, prev, short);
}

// Sorts owned strings in ascending byte order.
fn isStringAscLessThan(_: void, lhs: []u8, rhs: []u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

test "complete returns tracked file ids for untrack" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    try store_api.initializeVersionForFirstTrack(allocator, omohi_dir);
    const first_path = try createFileWithContentsAndResolve(tmp.dir, allocator, "a.txt", "one");
    defer allocator.free(first_path);
    const second_path = try createFileWithContentsAndResolve(tmp.dir, allocator, "b.txt", "two");
    defer allocator.free(second_path);
    const first = try store_api.track(allocator, omohi_dir, first_path);
    const second = try store_api.track(allocator, omohi_dir, second_path);

    const words = [_][]const u8{ "omohi", "untrack", "" };
    var list = try complete(allocator, omohi_dir, &words, 2);
    defer freeCandidateList(allocator, &list);

    try std.testing.expect(list.items.len >= 2);
    try std.testing.expect(containsCandidate(list.items, first.asSlice()));
    try std.testing.expect(containsCandidate(list.items, second.asSlice()));
}

test "complete returns commit ids for show and tags for tag rm" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    try store_api.initializeVersionForFirstTrack(allocator, omohi_dir);
    const tracked_path = try createFileWithContentsAndResolve(tmp.dir, allocator, "a.txt", "one");
    defer allocator.free(tracked_path);
    _ = try store_api.track(allocator, omohi_dir, tracked_path);
    try store_api.add(allocator, omohi_dir, tracked_path);
    const commit_id = try store_api.commit(allocator, omohi_dir, "first");
    try store_api.tagAdd(allocator, omohi_dir, commit_id.asSlice(), &.{ "prod", "release" });

    {
        const words = [_][]const u8{ "omohi", "show", "" };
        var list = try complete(allocator, omohi_dir, &words, 2);
        defer freeCandidateList(allocator, &list);
        try std.testing.expectEqual(@as(usize, 1), list.items.len);
        try std.testing.expectEqualStrings(commit_id.asSlice(), list.items[0]);
    }

    {
        const words = [_][]const u8{ "omohi", "tag", "rm", commit_id.asSlice(), "" };
        var list = try complete(allocator, omohi_dir, &words, 4);
        defer freeCandidateList(allocator, &list);
        try std.testing.expectEqual(@as(usize, 2), list.items.len);
        try std.testing.expectEqualStrings("prod", list.items[0]);
        try std.testing.expectEqualStrings("release", list.items[1]);
    }
}

test "complete returns staged paths for rm" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    try store_api.initializeVersionForFirstTrack(allocator, omohi_dir);
    const a_path = try createFileWithContentsAndResolve(tmp.dir, allocator, "a.txt", "one");
    defer allocator.free(a_path);
    const b_path = try createFileWithContentsAndResolve(tmp.dir, allocator, "b.txt", "two");
    defer allocator.free(b_path);
    _ = try store_api.track(allocator, omohi_dir, a_path);
    _ = try store_api.track(allocator, omohi_dir, b_path);
    try store_api.add(allocator, omohi_dir, b_path);
    try store_api.add(allocator, omohi_dir, a_path);

    const words = [_][]const u8{ "omohi", "rm", "" };
    var list = try complete(allocator, omohi_dir, &words, 2);
    defer freeCandidateList(allocator, &list);

    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqualStrings(a_path, list.items[0]);
    try std.testing.expectEqualStrings(b_path, list.items[1]);
}

test "complete returns journal for top-level command and help topic" {
    const allocator = std.testing.allocator;

    {
        const words = [_][]const u8{ "omohi", "jo" };
        var list = try complete(allocator, null, &words, 1);
        defer freeCandidateList(allocator, &list);

        try std.testing.expectEqual(@as(usize, 1), list.items.len);
        try std.testing.expectEqualStrings("journal", list.items[0]);
    }

    {
        const words = [_][]const u8{ "omohi", "help", "jo" };
        var list = try complete(allocator, null, &words, 2);
        defer freeCandidateList(allocator, &list);

        try std.testing.expectEqual(@as(usize, 1), list.items.len);
        try std.testing.expectEqualStrings("journal", list.items[0]);
    }
}

test "complete returns no candidates for journal arguments" {
    const allocator = std.testing.allocator;
    const words = [_][]const u8{ "omohi", "journal", "" };
    var list = try complete(allocator, null, &words, 2);
    defer freeCandidateList(allocator, &list);

    try std.testing.expectEqual(@as(usize, 0), list.items.len);
}

// TEST-ONLY: Creates a temporary file fixture and returns its resolved absolute path.
fn createFileWithContentsAndResolve(
    root: std.fs.Dir,
    allocator: std.mem.Allocator,
    name: []const u8,
    contents: []const u8,
) ![]u8 {
    var file = try root.createFile(name, .{ .truncate = true });
    defer file.close();
    try file.writeAll(contents);
    return try root.realpathAlloc(allocator, name);
}

// TEST-ONLY: Checks whether a completion test result contains an expected candidate.
fn containsCandidate(items: []const []u8, expected: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, expected)) return true;
    }
    return false;
}
