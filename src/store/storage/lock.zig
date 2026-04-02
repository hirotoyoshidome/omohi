const std = @import("std");
const testing = std.testing;
const utc = @import("time/utc.zig");

/// Errors when acquiring the LOCK file.
pub const AcquireLockError = error{
    LockAlreadyAcquired,
} || std.fs.File.OpenError || std.fs.File.WriteError || std.fs.File.SyncError || std.posix.UnexpectedError || utc.TimestampError || std.posix.GetHostNameError;

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
    const pid = std.posix.system.getpid();
    var hostname_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = try std.posix.gethostname(&hostname_buf);

    var buffer: [256]u8 = undefined;
    const written = std.fmt.bufPrint(
        &buffer,
        "pid={d}\ncreatedAt={s}\nhostname={s}\n",
        .{ pid, timestamp, hostname },
    ) catch unreachable;
    try file.writeAll(written);

    try file.sync();
    try syncDir(dir);
}

/// Deletes the LOCK file. Errors are ignored by design.
pub fn releaseLock(dir: std.fs.Dir) void {
    dir.deleteFile("LOCK") catch return;
    syncDir(dir) catch {};
}

// Fsyncs a directory and tolerates platforms that reject directory fsync.
fn syncDir(dir: std.fs.Dir) !void {
    const rc = std.posix.system.fsync(dir.fd);
    switch (std.posix.errno(rc)) {
        .SUCCESS, .BADF, .INVAL, .ROFS => return,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}

test "acquireLock writes owner info and releaseLock removes file" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try acquireLock(tmp.dir);
    const bytes = try tmp.dir.readFileAlloc(testing.allocator, "LOCK", 1024);
    defer testing.allocator.free(bytes);

    try testing.expect(std.mem.indexOf(u8, bytes, "pid=") != null);
    try testing.expect(std.mem.indexOf(u8, bytes, "createdAt=") != null);
    try testing.expect(std.mem.indexOf(u8, bytes, "hostname=") != null);

    try testing.expectError(error.LockAlreadyAcquired, acquireLock(tmp.dir));

    releaseLock(tmp.dir);
    try testing.expectError(error.FileNotFound, tmp.dir.openFile("LOCK", .{}));
}
