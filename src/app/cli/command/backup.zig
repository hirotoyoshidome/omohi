const std = @import("std");
const parser_types = @import("../parser/types.zig");
const command_types = @import("../runtime/types.zig");
const environment = @import("../environment.zig");
const path_resolver = @import("../path_resolver.zig");
const presenter = @import("../presenter/output.zig");
const exit_code = @import("../error/exit_code.zig");
const backup_ops = @import("../../../ops/backup_ops.zig");

// Runs the `backup` command and returns owned CLI output for the caller to free.
pub fn run(allocator: std.mem.Allocator, args: parser_types.BackupArgs) !command_types.CommandResult {
    var omohi = try environment.openOmohiDir(allocator, false);
    defer omohi.deinit(allocator);

    const archive_path = try path_resolver.resolveAbsolutePath(allocator, args.archive_path);
    defer allocator.free(archive_path);

    const result = try backup_ops.backup(
        allocator,
        omohi.dir,
        omohi.path,
        archive_path,
        args.max_size,
    );

    const output = try presenter.backupResult(allocator, archive_path, result);
    return .{ .output = output, .to_stderr = false, .exit_code = exit_code.ok };
}
