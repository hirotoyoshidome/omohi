const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../error/exit_code.zig");
const tag_ops = @import("../../../ops/tag_ops.zig");

// Runs the `tag add` command and returns owned CLI output for the caller to free.
pub fn run(allocator: std.mem.Allocator, args: parser_types.TagAddArgs) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    var before = tag_ops.list(allocator, omohi.dir, args.commit_id) catch |err| switch (err) {
        error.CommitNotFound => return commitNotFoundResult(allocator, args.commit_id),
        else => return err,
    };
    defer tag_ops.freeTagList(allocator, &before);

    tag_ops.add(allocator, omohi.dir, args.commit_id, args.tag_names) catch |err| switch (err) {
        error.CommitNotFound => return commitNotFoundResult(allocator, args.commit_id),
        else => return err,
    };

    var after = try tag_ops.list(allocator, omohi.dir, args.commit_id);
    defer tag_ops.freeTagList(allocator, &after);

    var added_count: usize = 0;
    for (after.items) |tag_name| {
        if (!containsTag(before.items, tag_name)) {
            added_count += 1;
        }
    }

    const output = try presenter.tagAddResult(allocator, args.commit_id, added_count, &after);
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}

// Reports whether the target tag is already present in the provided list.
fn containsTag(tags: []const []u8, target: []const u8) bool {
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

test "commitNotFoundResult includes commit id and use-case exit code" {
    const commit_id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const result = try commitNotFoundResult(std.testing.allocator, commit_id);
    defer std.testing.allocator.free(result.output);

    try std.testing.expect(result.to_stderr);
    try std.testing.expectEqual(exit_code.use_case_error, result.exit_code);
    try std.testing.expectEqualStrings(
        "Commit not found: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
        result.output,
    );
}
