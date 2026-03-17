const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const command_types = @import("../runtime/types.zig");
const exit_code = @import("../error/exit_code.zig");

pub fn run(allocator: std.mem.Allocator) !command_types.CommandResult {
    const output = try std.fmt.allocPrint(
        allocator,
        "omohi version {s} ({s}-{s})\n",
        .{
            build_options.app_version,
            @tagName(builtin.target.cpu.arch),
            @tagName(builtin.target.os.tag),
        },
    );
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}

test "version command returns formatted output" {
    var result = try run(std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(exit_code.ok, result.exit_code);
    try std.testing.expect(std.mem.startsWith(u8, result.output, "omohi version "));
    try std.testing.expect(std.mem.indexOf(u8, result.output, " (") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, ")\n") != null);
}
