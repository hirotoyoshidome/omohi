const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../error/exit_code.zig");
const show_ops = @import("../../../ops/show_ops.zig");

pub fn run(allocator: std.mem.Allocator, args: parser_types.ShowArgs) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    var details = try show_ops.show(allocator, omohi.dir, args.commit_id);
    defer show_ops.freeCommitDetails(allocator, &details);

    const output = try presenter.showResult(allocator, &details);
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}
