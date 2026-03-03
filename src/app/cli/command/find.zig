const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../exit_code.zig");
const find_ops = @import("../../../ops/find_ops.zig");

pub fn run(allocator: std.mem.Allocator, args: parser_types.FindArgs) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    var list = try find_ops.find(allocator, omohi.dir, args.tag, args.date);
    defer find_ops.freeCommitSummaryList(allocator, &list);

    const output = try presenter.findResult(allocator, &list);
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}
