const std = @import("std");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../error/exit_code.zig");
const track_ops = @import("../../../ops/track_ops.zig");

// Runs the `tracklist` command and returns owned CLI output for the caller to free.
pub fn run(allocator: std.mem.Allocator) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    var list = try track_ops.tracklist(allocator, omohi.dir);
    defer track_ops.freeTracklist(allocator, &list);

    const output = try presenter.tracklistResult(allocator, &list);
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}
