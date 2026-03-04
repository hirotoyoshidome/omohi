const std = @import("std");
const track_ops = @import("../../../ops/track_ops.zig");
const status_ops = @import("../../../ops/status_ops.zig");
const find_ops = @import("../../../ops/find_ops.zig");
const show_ops = @import("../../../ops/show_ops.zig");
const tag_ops = @import("../../../ops/tag_ops.zig");

pub fn message(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return allocator.dupe(u8, text);
}

pub fn trackResult(allocator: std.mem.Allocator, tracked_id: [32]u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "tracked: {s}\n", .{&tracked_id});
}

pub fn commitResult(allocator: std.mem.Allocator, commit_id: [64]u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "committed: {s}\n", .{&commit_id});
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
        try writer.print("{s} {s}\n", .{ entry.id.asSlice(), entry.path.asSlice() });
    }
    return out.toOwnedSlice();
}

pub fn statusResult(allocator: std.mem.Allocator, list: *const status_ops.StatusList) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    if (list.items.len == 0) {
        try writer.writeAll("no tracked files\n");
        return out.toOwnedSlice();
    }

    for (list.items) |entry| {
        try writer.print("{s} {s} {s}\n", .{
            entry.id.asSlice(),
            entry.path,
            statusLabel(entry.status),
        });
    }
    return out.toOwnedSlice();
}

fn statusLabel(kind: status_ops.StatusKind) []const u8 {
    return switch (kind) {
        .untracked => "untracked",
        .tracked => "tracked",
        .changed => "changed",
        .staged => "staged",
        .committed => "committed",
    };
}

pub fn findResult(allocator: std.mem.Allocator, list: *const find_ops.CommitSummaryList) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    if (list.items.len == 0) {
        try writer.writeAll("no commits\n");
        return out.toOwnedSlice();
    }

    for (list.items) |entry| {
        try writer.print("{s} {s} {s}\n", .{ entry.commit_id.asSlice(), entry.created_at, entry.message });
    }
    return out.toOwnedSlice();
}

pub fn showResult(allocator: std.mem.Allocator, details: *const show_ops.CommitDetails) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.print("commit: {s}\n", .{details.commit_id.asSlice()});
    try writer.print("snapshot: {s}\n", .{details.snapshot_id.asSlice()});
    try writer.print("createdAt: {s}\n", .{details.created_at});
    try writer.print("message: {s}\n", .{details.message});

    try writer.writeAll("entries:\n");
    for (details.entries.items) |entry| {
        try writer.print("- {s} {s}\n", .{ entry.path.asSlice(), entry.content_hash.asSlice() });
    }

    try writer.writeAll("tags:\n");
    for (details.tags.items) |tag| {
        try writer.print("- {s}\n", .{tag});
    }

    return out.toOwnedSlice();
}

pub fn tagListResult(allocator: std.mem.Allocator, tags: *const tag_ops.TagList) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    if (tags.items.len == 0) {
        try writer.writeAll("no tags\n");
        return out.toOwnedSlice();
    }

    for (tags.items) |tag| {
        try writer.print("{s}\n", .{tag});
    }
    return out.toOwnedSlice();
}

pub fn commitDryRunResult(allocator: std.mem.Allocator, staged_count: usize, staged_paths: []const []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.print("dry-run staged count: {d}\n", .{staged_count});
    for (staged_paths) |path| {
        try writer.print("- {s}\n", .{path});
    }
    return out.toOwnedSlice();
}
