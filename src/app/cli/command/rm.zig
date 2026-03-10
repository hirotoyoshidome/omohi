const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const path_resolver = @import("../path_resolver.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../error/exit_code.zig");
const rm_ops = @import("../../../ops/rm_ops.zig");

pub fn run(allocator: std.mem.Allocator, args: parser_types.RmArgs) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    const absolute_path = try path_resolver.resolveAbsolutePath(allocator, args.path);
    defer allocator.free(absolute_path);

    rm_ops.rm(allocator, omohi.dir, absolute_path) catch |err| switch (err) {
        error.TrackedFileNotFound => return trackedNotFoundResult(allocator, absolute_path),
        error.StagedFileNotFound => return stagedNotFoundResult(allocator, absolute_path),
        else => return err,
    };
    const output = try presenter.message(allocator, "unstaged\n");
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}

fn trackedNotFoundResult(
    allocator: std.mem.Allocator,
    absolute_path: []const u8,
) !command_types.CommandResult {
    const output = try std.fmt.allocPrint(allocator, "Tracked file not found: {s}\n", .{absolute_path});
    return .{ .output = output, .to_stderr = true, .exit_code = exit_code.use_case_error };
}

fn stagedNotFoundResult(
    allocator: std.mem.Allocator,
    absolute_path: []const u8,
) !command_types.CommandResult {
    const output = try std.fmt.allocPrint(allocator, "Staged file not found: {s}\n", .{absolute_path});
    return .{ .output = output, .to_stderr = true, .exit_code = exit_code.use_case_error };
}

test "trackedNotFoundResult returns expected message and exit code" {
    const result = try trackedNotFoundResult(std.testing.allocator, "/tmp/not-tracked.txt");
    defer std.testing.allocator.free(result.output);

    try std.testing.expect(result.to_stderr);
    try std.testing.expectEqual(exit_code.use_case_error, result.exit_code);
    try std.testing.expectEqualStrings("Tracked file not found: /tmp/not-tracked.txt\n", result.output);
}

test "stagedNotFoundResult returns expected message and exit code" {
    const result = try stagedNotFoundResult(std.testing.allocator, "/tmp/not-staged.txt");
    defer std.testing.allocator.free(result.output);

    try std.testing.expect(result.to_stderr);
    try std.testing.expectEqual(exit_code.use_case_error, result.exit_code);
    try std.testing.expectEqualStrings("Staged file not found: /tmp/not-staged.txt\n", result.output);
}
