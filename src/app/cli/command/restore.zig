const std = @import("std");

const parser_types = @import("../parser/types.zig");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const path_resolver = @import("../path_resolver.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../error/exit_code.zig");
const restore_ops = @import("../../../ops/restore_ops.zig");

// Runs the `restore` command and returns owned CLI output for the caller to free.
pub fn run(allocator: std.mem.Allocator, args: parser_types.RestoreArgs) !command_types.CommandResult {
    const store_path = try environment.resolveOmohiPath(allocator);
    defer allocator.free(store_path);

    const archive_path = try path_resolver.resolveAbsolutePath(allocator, args.archive_path);
    defer allocator.free(archive_path);

    var result = try restore_ops.restore(
        allocator,
        store_path,
        archive_path,
        args.replace,
        args.max_size,
    );
    defer restore_ops.freeRestoreResult(allocator, &result);

    const output = try presenter.restoreResult(allocator, archive_path, result);
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}
