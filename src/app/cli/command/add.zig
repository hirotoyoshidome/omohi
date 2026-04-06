const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const path_resolver = @import("../path_resolver.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../error/exit_code.zig");
const add_ops = @import("../../../ops/add_ops.zig");

// Runs the `add` command and returns owned CLI output for the caller to free.
pub fn run(allocator: std.mem.Allocator, args: parser_types.AddArgs) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    if (args.all) {
        var outcome = try add_ops.addAllTracked(allocator, omohi.dir);
        defer add_ops.freeAddOutcome(allocator, &outcome);

        const output = try presenter.addMultiResult(allocator, &outcome);
        return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
    }

    if (args.paths.len == 1) {
        const absolute_path = try path_resolver.resolveAbsolutePath(allocator, args.paths[0]);
        defer allocator.free(absolute_path);

        var outcome = add_ops.add(allocator, omohi.dir, absolute_path) catch |err| switch (err) {
            error.TrackedFileNotFound => return trackedNotFoundResult(allocator, absolute_path),
            error.MissingTrackedFile => return missingTrackedFileResult(allocator, absolute_path),
            else => return err,
        };
        defer add_ops.freeAddOutcome(allocator, &outcome);

        const output = try presenter.addResult(allocator, absolute_path, &outcome);
        return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
    }

    var combined = add_ops.AddOutcome.init(allocator);
    defer add_ops.freeAddOutcome(allocator, &combined);

    for (args.paths) |raw_path| {
        const absolute_path = try path_resolver.resolveAbsolutePath(allocator, raw_path);
        defer allocator.free(absolute_path);

        var outcome = add_ops.add(allocator, omohi.dir, absolute_path) catch |err| switch (err) {
            error.TrackedFileNotFound => return trackedNotFoundResult(allocator, absolute_path),
            error.MissingTrackedFile => return missingTrackedFileResult(allocator, absolute_path),
            else => return err,
        };
        errdefer add_ops.freeAddOutcome(allocator, &outcome);
        try adoptAddOutcome(&combined, &outcome);
    }

    const output = try presenter.addMultiResult(allocator, &combined);
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}

// Builds the owned stderr result for a missing tracked path.
fn missingTrackedFileResult(
    allocator: std.mem.Allocator,
    absolute_path: []const u8,
) !command_types.CommandResult {
    const output = try std.fmt.allocPrint(
        allocator,
        "Tracked file is missing: {s}\nUse `omohi untrack --missing` to clear missing tracked files explicitly.\n",
        .{absolute_path},
    );
    return .{ .output = output, .to_stderr = true, .exit_code = exit_code.use_case_error };
}

// Moves staged path ownership and counters into the combined result.
fn adoptAddOutcome(combined: *add_ops.AddOutcome, outcome: *add_ops.AddOutcome) !void {
    combined.skipped_untracked += outcome.skipped_untracked;
    combined.skipped_non_regular += outcome.skipped_non_regular;
    combined.skipped_already_staged += outcome.skipped_already_staged;
    combined.skipped_no_change += outcome.skipped_no_change;
    try combined.staged_paths.ensureUnusedCapacity(outcome.staged_paths.items.len);
    for (outcome.staged_paths.items) |path| {
        combined.staged_paths.appendAssumeCapacity(path);
    }
    outcome.staged_paths.items.len = 0;
    outcome.staged_paths.deinit();
}

// Builds the owned stderr result for an untracked path.
fn trackedNotFoundResult(
    allocator: std.mem.Allocator,
    absolute_path: []const u8,
) !command_types.CommandResult {
    const output = try std.fmt.allocPrint(allocator, "Tracked file not found: {s}\n", .{absolute_path});
    return .{ .output = output, .to_stderr = true, .exit_code = exit_code.use_case_error };
}

test "trackedNotFoundResult returns expected message and exit code" {
    const result = try trackedNotFoundResult(std.testing.allocator, "/tmp/not-tracked.txt");
    defer std.testing.allocator.free(result.output);

    try std.testing.expect(result.to_stderr);
    try std.testing.expectEqual(exit_code.use_case_error, result.exit_code);
    try std.testing.expectEqualStrings("Tracked file not found: /tmp/not-tracked.txt\n", result.output);
}

test "missingTrackedFileResult returns expected message and exit code" {
    const result = try missingTrackedFileResult(std.testing.allocator, "/tmp/missing.txt");
    defer std.testing.allocator.free(result.output);

    try std.testing.expect(result.to_stderr);
    try std.testing.expectEqual(exit_code.use_case_error, result.exit_code);
    try std.testing.expectEqualStrings(
        "Tracked file is missing: /tmp/missing.txt\n" ++
            "Use `omohi untrack --missing` to clear missing tracked files explicitly.\n",
        result.output,
    );
}
