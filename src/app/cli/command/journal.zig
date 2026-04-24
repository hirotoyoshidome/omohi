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

    const output = try presenter.journalResult(allocator, &lines);
    return .{
        .output = output,
        .to_stderr = false,
        .exit_code = exit_code.ok,
        .page_output = true,
    };
}

test "journal uses 500 item limit" {
    try std.testing.expectEqual(@as(usize, 500), default_limit);
}
