const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../error/exit_code.zig");
const tag_ops = @import("../../../ops/tag_ops.zig");

pub fn run(allocator: std.mem.Allocator, args: parser_types.TagAddArgs) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    try tag_ops.add(allocator, omohi.dir, args.commit_id, args.tag_names);
    const output = try presenter.message(allocator, "tags added\n");
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}
