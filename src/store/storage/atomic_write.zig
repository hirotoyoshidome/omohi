const std = @import("std");
const testing = std.testing;

/// Atomically writes `content` to `path` under the provided directory.
/// Memory: borrows `content`, caller retains ownership.
pub fn atomicWrite(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    path: []const u8,
    content: []const u8,
) !void {
    try ensureParentDirs(dir, path);

    const tmp_path = try makeTempPath(allocator, path);
    defer allocator.free(tmp_path);

    var file = try dir.createFile(tmp_path, .{
        .truncate = true,
        .exclusive = true,
    });
    defer file.close();

    errdefer dir.deleteFile(tmp_path) catch {};

    try file.writeAll(content);
    try file.sync();

    try dir.rename(tmp_path, path);
    try syncParentDir(dir, path);
}

fn ensureParentDirs(dir: std.fs.Dir, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| {
        if (parent.len == 0) return;
        try dir.makePath(parent);
    }
}

fn syncParentDir(dir: std.fs.Dir, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| {
        if (parent.len == 0) {
            try syncDir(dir);
            return;
        }
        var parent_dir = try dir.openDir(parent, .{});
        defer parent_dir.close();
        try syncDir(parent_dir);
    } else {
        try syncDir(dir);
    }
}

fn makeTempPath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var rand: [8]u8 = undefined;
    std.crypto.random.bytes(&rand);
    var hex: [rand.len * 2]u8 = undefined;
    encodeHexLower(&hex, &rand);
    return std.fmt.allocPrint(allocator, "{s}.tmp-{s}", .{ path, hex });
}

fn encodeHexLower(dest: []u8, source: []const u8) void {
    const alphabet = "0123456789abcdef";
    var di: usize = 0;
    for (source) |byte| {
        dest[di] = alphabet[@as(usize, byte >> 4)];
        dest[di + 1] = alphabet[@as(usize, byte & 0x0f)];
        di += 2;
    }
}

fn syncDir(dir: std.fs.Dir) !void {
    const rc = std.posix.system.fsync(dir.fd);
    switch (std.posix.errno(rc)) {
        .SUCCESS, .BADF, .INVAL, .ROFS => return,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}

test "atomicWrite writes new file and replaces existing file" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = testing.allocator;
    const first = "first-version";
    try atomicWrite(allocator, tmp.dir, "level1/file.txt", first);

    const content = try tmp.dir.readFileAlloc(allocator, "level1/file.txt", 1024);
    defer allocator.free(content);
    try testing.expectEqualStrings(first, content);

    const second = "second-version";
    try atomicWrite(allocator, tmp.dir, "level1/file.txt", second);
    const updated = try tmp.dir.readFileAlloc(allocator, "level1/file.txt", 1024);
    defer allocator.free(updated);
    try testing.expectEqualStrings(second, updated);
}
