const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("types.zig");
const environment = @import("../environment.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../exit_code.zig");
const tag_ops = @import("../../../ops/tag_ops.zig");

pub fn run(allocator: std.mem.Allocator, args: parser_types.TagLsArgs) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    var tags = try tag_ops.list(allocator, omohi.dir, args.commit_id);
    defer tag_ops.freeTagList(allocator, &tags);

    const output = try presenter.tagListResult(allocator, &tags);
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}
