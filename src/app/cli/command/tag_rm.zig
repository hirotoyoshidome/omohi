const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../error/exit_code.zig");
const tag_ops = @import("../../../ops/tag_ops.zig");

// Runs the `tag rm` command and returns owned CLI output for the caller to free.
pub fn run(allocator: std.mem.Allocator, args: parser_types.TagRmArgs) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    var before = tag_ops.list(allocator, omohi.dir, args.commit_id) catch |err| switch (err) {
        error.CommitNotFound => return commitNotFoundResult(allocator, args.commit_id),
        else => return err,
    };
    defer tag_ops.freeTagList(allocator, &before);

    if (before.items.len == 0) {
        const output = try presenter.tagRmResult(allocator, args.commit_id, 0, .no_tags, &before);
        return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
    }

    var matched_count: usize = 0;
    for (before.items) |tag_name| {
        if (containsTag(args.tag_names, tag_name)) {
            matched_count += 1;
        }
    }

    if (matched_count == 0) {
        const output = try presenter.tagRmResult(allocator, args.commit_id, 0, .no_matching, &before);
        return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
    }

    tag_ops.rm(allocator, omohi.dir, args.commit_id, args.tag_names) catch |err| switch (err) {
        error.CommitNotFound => return commitNotFoundResult(allocator, args.commit_id),
        else => return err,
    };

    var after = try tag_ops.list(allocator, omohi.dir, args.commit_id);
    defer tag_ops.freeTagList(allocator, &after);

    const output = try presenter.tagRmResult(allocator, args.commit_id, matched_count, .removed, &after);
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}

// Reports whether the target tag appears in the provided list.
fn containsTag(tags: []const []const u8, target: []const u8) bool {
    for (tags) |tag_name| {
        if (std.mem.eql(u8, tag_name, target)) return true;
    }
    return false;
}

// Builds the owned stderr result for a missing commit id.
fn commitNotFoundResult(
    allocator: std.mem.Allocator,
    commit_id: []const u8,
) !command_types.CommandResult {
    const output = try std.fmt.allocPrint(allocator, "Commit not found: {s}\n", .{commit_id});
    return .{ .output = output, .to_stderr = true, .exit_code = exit_code.use_case_error };
}
