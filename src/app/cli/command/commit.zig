const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("types.zig");
const environment = @import("../environment.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../exit_code.zig");
const commit_ops = @import("../../../ops/commit_ops.zig");
const status_ops = @import("../../../ops/status_ops.zig");
const tag_ops = @import("../../../ops/tag_ops.zig");

pub fn run(allocator: std.mem.Allocator, args: parser_types.CommitArgs) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    if (args.dry_run) {
        var list = try status_ops.status(allocator, omohi.dir);
        defer status_ops.freeStatusList(allocator, &list);

        var staged_paths = std.array_list.Managed([]const u8).init(allocator);
        defer {
            for (staged_paths.items) |path| allocator.free(path);
            staged_paths.deinit();
        }

        for (list.items) |entry| {
            if (entry.status == .staged) {
                try staged_paths.append(try allocator.dupe(u8, entry.path));
            }
        }

        const output = try presenter.commitDryRunResult(allocator, staged_paths.items.len, staged_paths.items);
        return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
    }

    const commit_id = try commit_ops.commit(allocator, omohi.dir, args.message);
    if (args.tags.len > 0) {
        try tag_ops.add(allocator, omohi.dir, &commit_id, args.tags);
    }

    const output = try presenter.commitResult(allocator, commit_id);
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}
