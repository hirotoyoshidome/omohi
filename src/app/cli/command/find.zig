const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../error/exit_code.zig");
const find_ops = @import("../../../ops/find_ops.zig");

const default_limit: usize = 500;

// Runs the `find` command and returns owned CLI output for the caller to free.
pub fn run(allocator: std.mem.Allocator, args: parser_types.FindArgs) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    const limit = args.limit orelse default_limit;
    var list = try find_ops.find(
        allocator,
        omohi.dir,
        args.tag,
        toOpsEmptyFilter(args.empty_filter),
        args.since_millis,
        args.until_millis,
        limit,
    );
    defer find_ops.freeCommitSummaryList(allocator, &list);

    const output = try presenter.findResult(allocator, &list, args);
    return .{
        .output = output,
        .to_stderr = false,
        .exit_code = exit_code.ok,
        .page_output = shouldPageOutput(args),
    };
}

// Converts the parser-level empty-commit filter into the ops/store representation.
fn toOpsEmptyFilter(filter: parser_types.FindEmptyFilter) find_ops.FindEmptyFilter {
    return switch (filter) {
        .all => .all,
        .empty_only => .empty_only,
        .non_empty_only => .non_empty_only,
    };
}

// Reports whether `find` output should be sent through the pager.
fn shouldPageOutput(args: parser_types.FindArgs) bool {
    return args.output == .text and args.limit == null;
}

test "find uses 500 item default limit" {
    try std.testing.expectEqual(@as(usize, 500), default_limit);
}

test "find enables paging only for default text output" {
    try std.testing.expect(shouldPageOutput(.{
        .tag = null,
        .empty_filter = .all,
        .since = null,
        .until = null,
        .since_millis = null,
        .until_millis = null,
        .limit = null,
        .output = .text,
        .fields = &.{},
    }));

    try std.testing.expect(!shouldPageOutput(.{
        .tag = null,
        .empty_filter = .all,
        .since = null,
        .until = null,
        .since_millis = null,
        .until_millis = null,
        .limit = 25,
        .output = .text,
        .fields = &.{},
    }));

    try std.testing.expect(!shouldPageOutput(.{
        .tag = null,
        .empty_filter = .all,
        .since = null,
        .until = null,
        .since_millis = null,
        .until_millis = null,
        .limit = null,
        .output = .json,
        .fields = &.{},
    }));
}
