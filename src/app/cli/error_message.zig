const std = @import("std");

pub fn forParseError(err: anyerror) []const u8 {
    return switch (err) {
        error.InvalidCommand => "Invalid command. Run `omohi help` to see available commands.",
        error.MissingArgument => "Missing required argument. Check command usage with `omohi help`.",
        error.UnexpectedArgument => "Unexpected argument. Check command usage with `omohi help`.",
        error.MissingValue => "Missing option value. Use `--key=value` or `--key value`.",
        error.UnknownOption => "Unknown option. Run `omohi help` to see supported options.",
        error.InvalidDate => "Invalid date format. Use YYYY-MM-DD.",
        else => "Invalid CLI input. Run `omohi help` to check usage.",
    };
}

pub fn forRuntimeError(err: anyerror) []const u8 {
    if (err == error.LockAlreadyAcquired) {
        return "Another operation is in progress because ~/.omohi/LOCK exists.\nIf no omohi process is running, remove ~/.omohi/LOCK manually and retry.";
    }
    if (err == error.VersionMismatch) {
        return "Store version mismatch detected in ~/.omohi/VERSION.\nThe store may be from a different format or corrupted.\nBack up ~/.omohi, then migrate or recreate the store.";
    }

    return switch (err) {
        error.NothingToCommit => "Nothing to commit. Stage files with `omohi add <path>` first.",
        error.OmohiNotInitialized => "Store is not initialized. Run `omohi track <path>` to create ~/.omohi.",
        error.CommitNotFound => "Commit not found. Check the commit ID with `omohi find`.",
        error.NotFound => "Target not found. Check the ID/path and try again.",
        error.AlreadyTracked => "The file is already tracked.",
        error.FileTooLarge => "File is too large to stage.",
        else => "Operation failed due to an unexpected system error.",
    };
}

test "runtime lock message includes manual cleanup guidance" {
    const text = forRuntimeError(error.LockAlreadyAcquired);
    try std.testing.expect(std.mem.indexOf(u8, text, "LOCK") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "manually") != null);
}

test "runtime version mismatch message includes cause and remedy" {
    const text = forRuntimeError(error.VersionMismatch);
    try std.testing.expect(std.mem.indexOf(u8, text, "mismatch") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "migrate or recreate") != null);
}

test "runtime NothingToCommit is user-friendly" {
    const text = forRuntimeError(error.NothingToCommit);
    try std.testing.expect(std.mem.indexOf(u8, text, "Nothing to commit") != null);
}
