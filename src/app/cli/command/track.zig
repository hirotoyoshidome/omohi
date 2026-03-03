const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const path_resolver = @import("../path_resolver.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../exit_code.zig");
const track_ops = @import("../../../ops/track_ops.zig");

pub fn run(allocator: std.mem.Allocator, args: parser_types.TrackArgs) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, true);
    defer omohi.deinit(allocator);

    const absolute_path = try path_resolver.resolveAbsolutePath(allocator, args.path);
    defer allocator.free(absolute_path);

    const tracked_id = try track_ops.track(allocator, omohi.dir, absolute_path);
    const output = try presenter.trackResult(allocator, tracked_id);

    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}
