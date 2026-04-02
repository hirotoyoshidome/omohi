const std = @import("std");
const exit_code = @import("exit_code.zig");

// Maps runtime errors to stable CLI exit codes.
pub fn exitCodeFor(err: anyerror) u8 {
    if (err == error.DataDestroyed) return exit_code.data_destroyed;
    if (err == error.MissingStoreVersion) return exit_code.data_destroyed;

    const name = @errorName(err);
    if (std.mem.startsWith(u8, name, "Invalid")) return exit_code.domain_error;

    if (err == error.NotFound or
        err == error.AlreadyTracked or
        err == error.NothingToCommit or
        err == error.LockAlreadyAcquired or
        err == error.CommitNotFound or
        err == error.OmohiNotInitialized or
        err == error.FileTooLarge)
    {
        return exit_code.use_case_error;
    }

    if (err == error.VersionMismatch) return exit_code.system_error;

    return exit_code.system_error;
}

test "VersionMismatch maps to system error exit code" {
    try std.testing.expectEqual(exit_code.system_error, exitCodeFor(error.VersionMismatch));
}

test "MissingStoreVersion maps to data destroyed exit code" {
    try std.testing.expectEqual(exit_code.data_destroyed, exitCodeFor(error.MissingStoreVersion));
}
