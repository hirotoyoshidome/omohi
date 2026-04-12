const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../error/exit_code.zig");
const commit_ops = @import("../../../ops/commit_ops.zig");
const status_ops = @import("../../../ops/status_ops.zig");
const tag_ops = @import("../../../ops/tag_ops.zig");

// Runs the `commit` command and returns owned CLI output for the caller to free.
pub fn run(allocator: std.mem.Allocator, args: parser_types.CommitArgs) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    if (args.dry_run) {
        var list = try status_ops.status(allocator, omohi.dir);
        defer status_ops.freeStatusList(allocator, &list);

        var staged_paths = try commit_ops.stagedPaths(allocator, omohi.dir);
        defer commit_ops.freeStringList(allocator, &staged_paths);

        var preview_entries = std.array_list.Managed(presenter.CommitDryRunEntry).init(allocator);
        defer preview_entries.deinit();

        for (staged_paths.items) |path| {
            try preview_entries.append(.{
                .path = path,
                .missing = statusForPath(&list, path) == .missing,
            });
        }

        const output = try presenter.commitDryRunResult(allocator, staged_paths.items.len, preview_entries.items);
        return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
    }

    const commit_id = try commit_ops.commit(allocator, omohi.dir, args.message, args.empty);
    if (args.tags.len > 0) {
        try tag_ops.add(allocator, omohi.dir, &commit_id, args.tags);
    }

    const output = try presenter.commitResult(allocator, commit_id);
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}

// Returns the current status for one tracked path when it exists in the list.
fn statusForPath(list: *const status_ops.StatusList, path: []const u8) status_ops.StatusKind {
    for (list.items) |entry| {
        if (std.mem.eql(u8, entry.path, path)) return entry.status;
    }
    return .tracked;
}
