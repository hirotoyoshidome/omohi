const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const path_resolver = @import("../path_resolver.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../error/exit_code.zig");
const track_ops = @import("../../../ops/track_ops.zig");

// Runs the `track` command and returns owned CLI output for the caller to free.
pub fn run(allocator: std.mem.Allocator, args: parser_types.TrackArgs) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, true);
    defer omohi.deinit(allocator);

    if (args.paths.len == 1) {
        const absolute_path = try path_resolver.resolveAbsolutePath(allocator, args.paths[0]);
        defer allocator.free(absolute_path);

        var outcome = try track_ops.track(allocator, omohi.dir, absolute_path);
        defer track_ops.freeTrackOutcome(allocator, &outcome);

        const output = try presenter.trackResult(allocator, absolute_path, &outcome);
        return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
    }

    var combined = track_ops.TrackOutcome.init(allocator);
    defer track_ops.freeTrackOutcome(allocator, &combined);

    for (args.paths) |raw_path| {
        const absolute_path = try path_resolver.resolveAbsolutePath(allocator, raw_path);
        defer allocator.free(absolute_path);

        var outcome = try track_ops.track(allocator, omohi.dir, absolute_path);
        errdefer track_ops.freeTrackOutcome(allocator, &outcome);
        try adoptTrackOutcome(&combined, &outcome);
    }

    const output = try presenter.trackMultiResult(allocator, &combined);

    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}

// Moves tracked path ownership and counters into the combined result.
fn adoptTrackOutcome(combined: *track_ops.TrackOutcome, outcome: *track_ops.TrackOutcome) !void {
    combined.skipped_paths += outcome.skipped_paths;
    try combined.tracked_paths.ensureUnusedCapacity(outcome.tracked_paths.items.len);
    for (outcome.tracked_paths.items) |path| {
        combined.tracked_paths.appendAssumeCapacity(path);
    }
    outcome.tracked_paths.items.len = 0;
    outcome.tracked_paths.deinit();
}
