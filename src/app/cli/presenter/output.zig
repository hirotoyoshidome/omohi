const std = @import("std");
const add_ops = @import("../../../ops/add_ops.zig");
const rm_ops = @import("../../../ops/rm_ops.zig");
const track_ops = @import("../../../ops/track_ops.zig");
const status_ops = @import("../../../ops/status_ops.zig");
const find_ops = @import("../../../ops/find_ops.zig");
const show_ops = @import("../../../ops/show_ops.zig");
const tag_ops = @import("../../../ops/tag_ops.zig");

pub const TagRemoveOutcome = enum {
    no_tags,
    no_matching,
    removed,
};

pub fn message(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return allocator.dupe(u8, text);
}

pub fn trackResult(
    allocator: std.mem.Allocator,
    absolute_path: []const u8,
    outcome: *const track_ops.TrackOutcome,
) ![]u8 {
    if (outcome.tracked_paths.items.len == 1 and outcome.skipped_paths == 0 and
        std.mem.eql(u8, outcome.tracked_paths.items[0], absolute_path))
    {
        return std.fmt.allocPrint(allocator, "Tracked: {s}\n", .{absolute_path});
    }

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.print("Tracked {d} file(s) under {s}\n", .{ outcome.tracked_paths.items.len, absolute_path });
    for (outcome.tracked_paths.items) |path| {
        try writer.print("- {s}\n", .{path});
    }
    if (outcome.skipped_paths != 0) {
        try writer.print("Skipped already tracked file(s): {d}\n", .{outcome.skipped_paths});
    }

    return out.toOwnedSlice();
}

pub fn untrackResult(allocator: std.mem.Allocator, absolute_path: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "Untracked: {s}\n", .{absolute_path});
}

pub fn addResult(
    allocator: std.mem.Allocator,
    absolute_path: []const u8,
    outcome: *const add_ops.AddOutcome,
) ![]u8 {
    if (outcome.staged_paths.items.len == 1 and
        outcome.skipped_untracked == 0 and
        outcome.skipped_non_regular == 0 and
        outcome.skipped_already_staged == 0 and
        std.mem.eql(u8, outcome.staged_paths.items[0], absolute_path))
    {
        return std.fmt.allocPrint(allocator, "Staged: {s}\n", .{absolute_path});
    }

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.print("Staged {d} file(s) under {s}\n", .{ outcome.staged_paths.items.len, absolute_path });
    for (outcome.staged_paths.items) |path| {
        try writer.print("- {s}\n", .{path});
    }
    if (outcome.skipped_untracked != 0) {
        try writer.print("Skipped untracked file(s): {d}\n", .{outcome.skipped_untracked});
    }
    if (outcome.skipped_already_staged != 0) {
        try writer.print("Skipped already staged file(s): {d}\n", .{outcome.skipped_already_staged});
    }
    if (outcome.skipped_non_regular != 0) {
        try writer.print("Skipped non-regular entry(s): {d}\n", .{outcome.skipped_non_regular});
    }

    return out.toOwnedSlice();
}

pub fn rmResult(
    allocator: std.mem.Allocator,
    absolute_path: []const u8,
    outcome: *const rm_ops.RmOutcome,
) ![]u8 {
    if (outcome.unstaged_paths.items.len == 1 and
        outcome.skipped_untracked == 0 and
        outcome.skipped_not_staged == 0 and
        outcome.skipped_non_regular == 0 and
        std.mem.eql(u8, outcome.unstaged_paths.items[0], absolute_path))
    {
        return std.fmt.allocPrint(allocator, "Unstaged: {s}\n", .{absolute_path});
    }

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.print("Unstaged {d} file(s) under {s}\n", .{ outcome.unstaged_paths.items.len, absolute_path });
    for (outcome.unstaged_paths.items) |path| {
        try writer.print("- {s}\n", .{path});
    }
    if (outcome.skipped_untracked != 0) {
        try writer.print("Skipped untracked file(s): {d}\n", .{outcome.skipped_untracked});
    }
    if (outcome.skipped_not_staged != 0) {
        try writer.print("Skipped non-staged file(s): {d}\n", .{outcome.skipped_not_staged});
    }
    if (outcome.skipped_non_regular != 0) {
        try writer.print("Skipped non-regular entry(s): {d}\n", .{outcome.skipped_non_regular});
    }

    return out.toOwnedSlice();
}

pub fn commitResult(allocator: std.mem.Allocator, commit_id: [64]u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "Committed {s}.\n", .{&commit_id});
}

pub fn tracklistResult(allocator: std.mem.Allocator, list: *const track_ops.TrackedList) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    if (list.items.len == 0) {
        try writer.writeAll("no tracked files\n");
        return out.toOwnedSlice();
    }

    for (list.items) |entry| {
        try writer.print("{s}: {s}\n", .{ entry.id.asSlice(), entry.path.asSlice() });
    }
    return out.toOwnedSlice();
}

pub fn statusResult(allocator: std.mem.Allocator, list: *const status_ops.StatusList) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.writeAll("Status retrieved successfully.\n");

    try writer.writeAll("Staged files:\n");
    var staged_count: usize = 0;
    for (list.items) |entry| {
        if (entry.status != .staged) continue;
        staged_count += 1;
        try writer.print("- {s}\n", .{entry.path});
    }
    if (staged_count == 0) {
        try writer.writeAll("- (none)\n");
    }

    try writer.writeAll("Changed tracked files:\n");
    var changed_count: usize = 0;
    for (list.items) |entry| {
        if (entry.status != .tracked and entry.status != .changed) continue;
        changed_count += 1;
        try writer.print("- {s}\n", .{entry.path});
    }
    if (changed_count == 0) {
        try writer.writeAll("- (none)\n");
    }

    return out.toOwnedSlice();
}

pub fn findResult(
    allocator: std.mem.Allocator,
    list: *const find_ops.CommitSummaryList,
    tag: ?[]const u8,
    date: ?[]const u8,
) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    if (list.items.len == 0) {
        try writer.writeAll("no commits\n");
        return out.toOwnedSlice();
    }

    if (tag) |tag_name| {
        if (date) |date_value| {
            try writer.print(
                "Found {d} commit(s) for tag {s} and date {s}.\n",
                .{ list.items.len, tag_name, date_value },
            );
        } else {
            try writer.print("Found {d} commit(s) for tag {s}.\n", .{ list.items.len, tag_name });
        }
    } else if (date) |date_value| {
        try writer.print("Found {d} commit(s) for date {s}.\n", .{ list.items.len, date_value });
    } else {
        try writer.print("Found {d} commit(s).\n", .{list.items.len});
    }

    for (list.items) |entry| {
        try writer.print("- {s}: {s}\n", .{ entry.commit_id.asSlice(), entry.message });
    }
    return out.toOwnedSlice();
}

pub fn showResult(allocator: std.mem.Allocator, details: *const show_ops.CommitDetails) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.print("Found commit {s}.\n", .{details.commit_id.asSlice()});
    try writer.print("{s} {s}\n", .{ details.commit_id.asSlice(), details.message });

    try writer.print("snapshot: {s}\n", .{details.snapshot_id.asSlice()});
    try writer.print("createdAt: {s}\n", .{details.created_at});

    try writer.writeAll("entries:\n");
    for (details.entries.items) |entry| {
        try writer.print("- {s} {s}\n", .{ entry.path.asSlice(), entry.content_hash.asSlice() });
    }

    try writer.writeAll("tags:\n");
    for (details.tags.items) |tag_name| {
        try writer.print("- {s}\n", .{tag_name});
    }

    return out.toOwnedSlice();
}

pub fn tagListResult(allocator: std.mem.Allocator, commit_id: []const u8, tags: *const tag_ops.TagList) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.print("Found {d} tag(s) for commit {s}.\n", .{ tags.items.len, commit_id });
    try writeTagCsvLine(writer, tags.items);

    return out.toOwnedSlice();
}

pub fn tagAddResult(
    allocator: std.mem.Allocator,
    commit_id: []const u8,
    added_count: usize,
    tags: *const tag_ops.TagList,
) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    if (added_count == 0) {
        try writer.print(
            "No new tags were added; commit {s} already has the specified tags.\n",
            .{commit_id},
        );
    } else {
        try writer.print("Added {d} tag(s) to commit {s}.\n", .{ added_count, commit_id });
    }
    try writeTagCsvLine(writer, tags.items);

    return out.toOwnedSlice();
}

pub fn tagRmResult(
    allocator: std.mem.Allocator,
    commit_id: []const u8,
    removed_count: usize,
    outcome: TagRemoveOutcome,
    tags: *const tag_ops.TagList,
) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    switch (outcome) {
        .no_tags => try writer.print("Commit {s} has no tags to remove.\n", .{commit_id}),
        .no_matching => try writer.print("No matching tags found to remove from commit {s}.\n", .{commit_id}),
        .removed => try writer.print("Removed {d} tag(s) from commit {s}.\n", .{ removed_count, commit_id }),
    }
    try writeTagCsvLine(writer, tags.items);

    return out.toOwnedSlice();
}

pub fn commitDryRunResult(allocator: std.mem.Allocator, staged_count: usize, staged_paths: []const []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.writeAll("Dry run: commit prepared but not written.\n");
    try writer.print("dry-run staged count: {d}\n", .{staged_count});
    for (staged_paths) |path| {
        try writer.print("- {s}\n", .{path});
    }
    return out.toOwnedSlice();
}

fn writeTagCsvLine(writer: anytype, tags: []const []u8) !void {
    if (tags.len == 0) {
        try writer.writeAll("(none)\n");
        return;
    }

    for (tags, 0..) |tag_name, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.writeAll(tag_name);
    }
    try writer.writeByte('\n');
}

fn filled32(ch: u8) [32]u8 {
    var value: [32]u8 = undefined;
    @memset(&value, ch);
    return value;
}

fn filled64(ch: u8) [64]u8 {
    var value: [64]u8 = undefined;
    @memset(&value, ch);
    return value;
}

test "trackResult follows migration contract" {
    var outcome = track_ops.TrackOutcome.init(std.testing.allocator);
    defer track_ops.freeTrackOutcome(std.testing.allocator, &outcome);
    try outcome.tracked_paths.append(try std.testing.allocator.dupe(u8, "/tmp/a.txt"));

    const output = try trackResult(std.testing.allocator, "/tmp/a.txt", &outcome);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("Tracked: /tmp/a.txt\n", output);
}

test "trackResult renders directory expansion summary" {
    var outcome = track_ops.TrackOutcome.init(std.testing.allocator);
    defer track_ops.freeTrackOutcome(std.testing.allocator, &outcome);
    try outcome.tracked_paths.append(try std.testing.allocator.dupe(u8, "/tmp/root/a.txt"));
    try outcome.tracked_paths.append(try std.testing.allocator.dupe(u8, "/tmp/root/sub/b.txt"));
    outcome.skipped_paths = 1;

    const output = try trackResult(std.testing.allocator, "/tmp/root", &outcome);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Tracked 2 file(s) under /tmp/root\n" ++
            "- /tmp/root/a.txt\n" ++
            "- /tmp/root/sub/b.txt\n" ++
            "Skipped already tracked file(s): 1\n",
        output,
    );
}

test "untrackResult follows migration contract" {
    const output = try untrackResult(std.testing.allocator, "/tmp/a.txt");
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("Untracked: /tmp/a.txt\n", output);
}

test "addResult follows migration contract" {
    var outcome = add_ops.AddOutcome.init(std.testing.allocator);
    defer add_ops.freeAddOutcome(std.testing.allocator, &outcome);
    try outcome.staged_paths.append(try std.testing.allocator.dupe(u8, "/tmp/a.txt"));

    const output = try addResult(std.testing.allocator, "/tmp/a.txt", &outcome);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("Staged: /tmp/a.txt\n", output);
}

test "rmResult follows migration contract" {
    var outcome = rm_ops.RmOutcome.init(std.testing.allocator);
    defer rm_ops.freeRmOutcome(std.testing.allocator, &outcome);
    try outcome.unstaged_paths.append(try std.testing.allocator.dupe(u8, "/tmp/a.txt"));

    const output = try rmResult(std.testing.allocator, "/tmp/a.txt", &outcome);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("Unstaged: /tmp/a.txt\n", output);
}

test "addResult renders directory summary" {
    var outcome = add_ops.AddOutcome.init(std.testing.allocator);
    defer add_ops.freeAddOutcome(std.testing.allocator, &outcome);
    try outcome.staged_paths.append(try std.testing.allocator.dupe(u8, "/tmp/root/a.txt"));
    outcome.skipped_untracked = 2;
    outcome.skipped_already_staged = 1;

    const output = try addResult(std.testing.allocator, "/tmp/root", &outcome);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Staged 1 file(s) under /tmp/root\n" ++
            "- /tmp/root/a.txt\n" ++
            "Skipped untracked file(s): 2\n" ++
            "Skipped already staged file(s): 1\n",
        output,
    );
}

test "rmResult renders directory summary" {
    var outcome = rm_ops.RmOutcome.init(std.testing.allocator);
    defer rm_ops.freeRmOutcome(std.testing.allocator, &outcome);
    try outcome.unstaged_paths.append(try std.testing.allocator.dupe(u8, "/tmp/root/a.txt"));
    outcome.skipped_not_staged = 1;
    outcome.skipped_untracked = 2;

    const output = try rmResult(std.testing.allocator, "/tmp/root", &outcome);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Unstaged 1 file(s) under /tmp/root\n" ++
            "- /tmp/root/a.txt\n" ++
            "Skipped untracked file(s): 2\n" ++
            "Skipped non-staged file(s): 1\n",
        output,
    );
}

test "commitResult follows migration contract" {
    var commit_id: [64]u8 = undefined;
    @memset(&commit_id, 'a');

    const output = try commitResult(std.testing.allocator, commit_id);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Committed aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.\n",
        output,
    );
}

test "tracklistResult renders id and path" {
    var list = track_ops.TrackedList.init(std.testing.allocator);
    defer {
        for (list.items) |entry| std.testing.allocator.free(@constCast(entry.path.asSlice()));
        list.deinit();
    }

    const path = try std.testing.allocator.dupe(u8, "/tmp/tracked.txt");
    try list.append(.{
        .id = .{ .value = filled32('a') },
        .path = .{ .value = path },
    });

    const output = try tracklistResult(std.testing.allocator, &list);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa: /tmp/tracked.txt\n",
        output,
    );
}

test "findResult renders migration heading and entries" {
    var list = find_ops.CommitSummaryList.init(std.testing.allocator);
    defer {
        find_ops.freeCommitSummaryList(std.testing.allocator, &list);
    }

    try list.append(.{
        .commit_id = .{ .value = filled64('a') },
        .message = try std.testing.allocator.dupe(u8, "first"),
        .created_at = try std.testing.allocator.dupe(u8, "2026-03-10T00:00:00.000Z"),
    });

    const output = try findResult(std.testing.allocator, &list, "release", null);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Found 1 commit(s) for tag release.\n" ++
            "- aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa: first\n",
        output,
    );
}

test "statusResult groups staged and changed tracked files" {
    var list = status_ops.StatusList.init(std.testing.allocator);
    defer {
        for (list.items) |entry| std.testing.allocator.free(entry.path);
        list.deinit();
    }

    try list.append(.{
        .id = .{ .value = filled32('a') },
        .path = try std.testing.allocator.dupe(u8, "/tmp/staged.txt"),
        .status = .staged,
    });
    try list.append(.{
        .id = .{ .value = filled32('b') },
        .path = try std.testing.allocator.dupe(u8, "/tmp/changed.txt"),
        .status = .changed,
    });

    const output = try statusResult(std.testing.allocator, &list);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Status retrieved successfully.\n" ++
            "Staged files:\n" ++
            "- /tmp/staged.txt\n" ++
            "Changed tracked files:\n" ++
            "- /tmp/changed.txt\n",
        output,
    );
}

test "tagAddResult renders no-new-tags branch with csv" {
    var tags = tag_ops.TagList.init(std.testing.allocator);
    defer {
        for (tags.items) |tag_name| std.testing.allocator.free(tag_name);
        tags.deinit();
    }

    try tags.append(try std.testing.allocator.dupe(u8, "mobile"));
    try tags.append(try std.testing.allocator.dupe(u8, "release"));

    const output = try tagAddResult(
        std.testing.allocator,
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        0,
        &tags,
    );
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "No new tags were added; commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa already has the specified tags.\n" ++
            "mobile,release\n",
        output,
    );
}

test "tagListResult renders count and csv line" {
    var tags = tag_ops.TagList.init(std.testing.allocator);
    defer {
        for (tags.items) |tag_name| std.testing.allocator.free(tag_name);
        tags.deinit();
    }

    try tags.append(try std.testing.allocator.dupe(u8, "mobile"));
    try tags.append(try std.testing.allocator.dupe(u8, "release"));

    const output = try tagListResult(
        std.testing.allocator,
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        &tags,
    );
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Found 2 tag(s) for commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.\n" ++
            "mobile,release\n",
        output,
    );
}

test "tagRmResult renders no-tags branch" {
    var tags = tag_ops.TagList.init(std.testing.allocator);
    defer tags.deinit();

    const output = try tagRmResult(
        std.testing.allocator,
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        0,
        .no_tags,
        &tags,
    );
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Commit aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa has no tags to remove.\n" ++
            "(none)\n",
        output,
    );
}

test "commitDryRunResult starts with migration message" {
    const paths = [_][]const u8{ "/tmp/a.txt", "/tmp/b.txt" };
    const output = try commitDryRunResult(std.testing.allocator, paths.len, &paths);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(
        "Dry run: commit prepared but not written.\n" ++
            "dry-run staged count: 2\n" ++
            "- /tmp/a.txt\n" ++
            "- /tmp/b.txt\n",
        output,
    );
}
