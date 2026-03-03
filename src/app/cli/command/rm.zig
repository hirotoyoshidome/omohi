const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("types.zig");
const environment = @import("../environment.zig");
const path_resolver = @import("../path_resolver.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../exit_code.zig");
const rm_ops = @import("../../../ops/rm_ops.zig");

pub fn run(allocator: std.mem.Allocator, args: parser_types.RmArgs) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    const absolute_path = try path_resolver.resolveAbsolutePath(allocator, args.path);
    defer allocator.free(absolute_path);

    var source = try path_resolver.openSourcePath(absolute_path);
    defer source.source_dir.close();

    try rm_ops.rm(allocator, omohi.dir, source.source_dir, source.relative_path);
    const output = try presenter.message(allocator, "unstaged\n");
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}
