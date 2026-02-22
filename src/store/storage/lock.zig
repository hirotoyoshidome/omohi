const std = @import("std");
const utc = @import("../time/utc.zig");

/// Errors when acquiring the LOCK file.
pub const AcquireLockError = error{
    LockAlreadyAcquired,
} || std.fs.File.OpenError || std.fs.File.WriteError || std.fs.File.SyncError || std.fs.Dir.SyncError || utc.TimestampError || std.posix.GetHostNameError;

/// Atomically acquires `.omohi/LOCK`.
pub fn acquireLock(dir: std.fs.Dir) AcquireLockError!void {
    var file = dir.createFile("LOCK", .{
        .truncate = false,
        .exclusive = true,
    }) catch |err| switch (err) {
        error.PathAlreadyExists => return error.LockAlreadyAcquired,
        else => return err,
    };
    defer file.close();

    const timestamp = try utc.nowIso8601Utc();
    const pid = std.posix.getpid();
    var hostname_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = try std.posix.gethostname(&hostname_buf);

    var writer = file.writer();
    try writer.print("pid={d}\ncreatedAt={s}\nhostname={s}\n", .{
        pid,
        timestamp,
        hostname,
    });

    try file.sync();
    try dir.sync();
}

/// Deletes the LOCK file. Errors are ignored by design.
pub fn releaseLock(dir: std.fs.Dir) void {
    dir.deleteFile("LOCK") catch return;
    dir.sync() catch {};
}
