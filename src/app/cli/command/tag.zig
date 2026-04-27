const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../error/exit_code.zig");
const tag_ops = @import("../../../ops/tag_ops.zig");

// Runs the `tag` command and returns owned CLI output for the caller to free.
pub fn run(allocator: std.mem.Allocator, args: parser_types.TagArgs) !command_types.CommandResult {
    _ = args;

    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    var tags = try tag_ops.listAll(allocator, omohi.dir);
    defer tag_ops.freeTagNameList(allocator, &tags);

    const output = try presenter.tagNameListResult(allocator, &tags);
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}
