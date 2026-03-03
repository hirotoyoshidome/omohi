const std = @import("std");
const command_types = @import("../runtime/types.zig");
const exit_code = @import("../error/exit_code.zig");
const catalog = @import("help/catalog.zig");

pub fn run(allocator: std.mem.Allocator) !command_types.CommandResult {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.writeAll("omohi commands:\n");
    for (catalog.all) |spec| {
        try writer.print("  {s}\n", .{spec.usage});
    }

    return .{ .output = try out.toOwnedSlice(), .to_stderr = false, .exit_code = exit_code.ok };
}

test "help includes all public commands" {
    var result = try run(std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(std.mem.indexOf(u8, result.output, "track <path>") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "tag rm <commitId> <tagNames...>") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "help") != null);
}
