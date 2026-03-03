const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("types.zig");
const environment = @import("../environment.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../exit_code.zig");
const track_ops = @import("../../../ops/track_ops.zig");

pub fn run(allocator: std.mem.Allocator, args: parser_types.UntrackArgs) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    try track_ops.untrack(allocator, omohi.dir, args.tracked_file_id);
    const output = try presenter.message(allocator, "untracked\n");
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}
