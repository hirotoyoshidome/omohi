const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const path_resolver = @import("../path_resolver.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../error/exit_code.zig");
const rm_ops = @import("../../../ops/rm_ops.zig");

// Runs the `rm` command and returns owned CLI output for the caller to free.
pub fn run(allocator: std.mem.Allocator, args: parser_types.RmArgs) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    if (args.all) {
        var outcome = try rm_ops.rmAllStaged(allocator, omohi.dir);
        defer rm_ops.freeRmOutcome(allocator, &outcome);

        const output = try presenter.rmMultiResult(allocator, &outcome);
        return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
    }

    if (args.paths.len == 1) {
        const absolute_path = try path_resolver.resolveAbsolutePath(allocator, args.paths[0]);
        defer allocator.free(absolute_path);

        var outcome = rm_ops.rm(allocator, omohi.dir, absolute_path) catch |err| switch (err) {
            error.TrackedFileNotFound => return trackedNotFoundResult(allocator, absolute_path),
            error.StagedFileNotFound => return stagedNotFoundResult(allocator, absolute_path),
            else => return err,
        };
        defer rm_ops.freeRmOutcome(allocator, &outcome);

        const output = try presenter.rmResult(allocator, absolute_path, &outcome);
        return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
    }

    var combined = rm_ops.RmOutcome.init(allocator);
    defer rm_ops.freeRmOutcome(allocator, &combined);

    for (args.paths) |raw_path| {
        const absolute_path = try path_resolver.resolveAbsolutePath(allocator, raw_path);
        defer allocator.free(absolute_path);

        var outcome = rm_ops.rm(allocator, omohi.dir, absolute_path) catch |err| switch (err) {
            error.TrackedFileNotFound => return trackedNotFoundResult(allocator, absolute_path),
            error.StagedFileNotFound => return stagedNotFoundResult(allocator, absolute_path),
            else => return err,
        };
        errdefer rm_ops.freeRmOutcome(allocator, &outcome);
        try adoptRmOutcome(&combined, &outcome);
    }

    const output = try presenter.rmMultiResult(allocator, &combined);
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}

// Moves unstaged path ownership and counters into the combined result.
fn adoptRmOutcome(combined: *rm_ops.RmOutcome, outcome: *rm_ops.RmOutcome) !void {
    combined.skipped_untracked += outcome.skipped_untracked;
    combined.skipped_not_staged += outcome.skipped_not_staged;
    combined.skipped_non_regular += outcome.skipped_non_regular;
    try combined.unstaged_paths.ensureUnusedCapacity(outcome.unstaged_paths.items.len);
    for (outcome.unstaged_paths.items) |path| {
        combined.unstaged_paths.appendAssumeCapacity(path);
    }
    outcome.unstaged_paths.items.len = 0;
    outcome.unstaged_paths.deinit();
}

// Builds the owned stderr result for a tracked path that was not found.
fn trackedNotFoundResult(
    allocator: std.mem.Allocator,
    absolute_path: []const u8,
) !command_types.CommandResult {
    const output = try std.fmt.allocPrint(allocator, "Tracked file not found: {s}\n", .{absolute_path});
    return .{ .output = output, .to_stderr = true, .exit_code = exit_code.use_case_error };
}

// Builds the owned stderr result for a path that is tracked but not staged.
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
