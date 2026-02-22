const std = @import("std");

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
            try dir.sync();
            return;
        }
        var parent_dir = try dir.openDir(parent, .{});
        defer parent_dir.close();
        try parent_dir.sync();
    } else {
        try dir.sync();
    }
}

fn makeTempPath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var rand: [8]u8 = undefined;
    std.crypto.random.bytes(&rand);
    return std.fmt.allocPrint(allocator, "{s}.tmp-{s}", .{
        path,
        std.fmt.fmtSliceHexLower(&rand),
    });
}
