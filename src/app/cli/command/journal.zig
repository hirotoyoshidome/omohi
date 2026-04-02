const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../error/exit_code.zig");
const journal_ops = @import("../../../ops/journal_ops.zig");

const default_limit: usize = 500;

// Runs the `journal` command and marks the owned output for pager-friendly display.
pub fn run(allocator: std.mem.Allocator, args: parser_types.JournalArgs) !command_types.CommandResult {
    _ = args;

    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    var lines = try journal_ops.journal(allocator, omohi.dir, default_limit);
    defer journal_ops.freeJournalList(allocator, &lines);

    const output = try journalResult(allocator, &lines);
    return .{
        .output = output,
        .to_stderr = false,
        .exit_code = exit_code.ok,
        .page_output = true,
    };
}

// Renders journal lines into owned output and returns a fallback message when empty.
fn journalResult(allocator: std.mem.Allocator, lines: *const journal_ops.JournalList) ![]u8 {
    if (lines.items.len == 0) return presenter.message(allocator, "no journal entries\n");

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    for (lines.items) |line| {
        try writer.print("{s}\n", .{line});
    }

    return out.toOwnedSlice();
}

test "journalResult formats lines with trailing newlines" {
    var lines = journal_ops.JournalList.init(std.testing.allocator);
    defer journal_ops.freeJournalList(std.testing.allocator, &lines);

    try lines.append(try std.testing.allocator.dupe(u8, "line-a"));
    try lines.append(try std.testing.allocator.dupe(u8, "line-b"));

    const output = try journalResult(std.testing.allocator, &lines);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("line-a\nline-b\n", output);
}

test "journalResult returns empty message when no entries exist" {
    var lines = journal_ops.JournalList.init(std.testing.allocator);
    defer journal_ops.freeJournalList(std.testing.allocator, &lines);

    const output = try journalResult(std.testing.allocator, &lines);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("no journal entries\n", output);
}

test "journal uses 500 item limit" {
    try std.testing.expectEqual(@as(usize, 500), default_limit);
}
