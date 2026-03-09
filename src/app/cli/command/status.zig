const std = @import("std");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../error/exit_code.zig");
const status_ops = @import("../../../ops/status_ops.zig");

pub fn run(allocator: std.mem.Allocator) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    var list = try status_ops.status(allocator, omohi.dir);
    defer status_ops.freeStatusList(allocator, &list);

    const output = try presenter.statusResult(allocator, &list);
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}
