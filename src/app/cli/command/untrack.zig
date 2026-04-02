const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../error/exit_code.zig");
const track_ops = @import("../../../ops/track_ops.zig");

// Runs the `untrack` command and returns owned CLI output for the caller to free.
pub fn run(allocator: std.mem.Allocator, args: parser_types.UntrackArgs) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    var list = try track_ops.tracklist(allocator, omohi.dir);
    defer track_ops.freeTracklist(allocator, &list);

    var tracked_path: ?[]const u8 = null;
    for (list.items) |entry| {
        if (std.ascii.eqlIgnoreCase(entry.id.asSlice(), args.tracked_file_id)) {
            tracked_path = entry.path.asSlice();
            break;
        }
    }

    try track_ops.untrack(allocator, omohi.dir, args.tracked_file_id);
    const output = try presenter.untrackResult(allocator, tracked_path orelse args.tracked_file_id);
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}
