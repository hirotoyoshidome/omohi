const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const exit_code = @import("../error/exit_code.zig");
const completion_ops = @import("../../../ops/completion_ops.zig");

pub fn run(allocator: std.mem.Allocator, args: parser_types.CompleteArgs) !command_types.CommandResult {
    var list = if (completion_ops.requiresStore(args.words, args.index)) blk: {
        var omohi = try environment.openOmohiDir(allocator, false);
        defer omohi.deinit(allocator);
        break :blk try completion_ops.complete(allocator, omohi.dir, args.words, args.index);
    } else try completion_ops.complete(allocator, null, args.words, args.index);
    defer completion_ops.freeCandidateList(allocator, &list);

    const output = try renderCandidates(allocator, list.items);
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}

fn renderCandidates(allocator: std.mem.Allocator, items: []const []u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    for (items) |item| {
        try out.writer().writeAll(item);
        try out.writer().writeByte('\n');
    }
    return out.toOwnedSlice();
}

test "complete command renders one candidate per line" {
    var result = try run(std.testing.allocator, .{
        .index = 1,
        .words = &.{ "omohi", "sh" },
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("show\n", result.output);
}
