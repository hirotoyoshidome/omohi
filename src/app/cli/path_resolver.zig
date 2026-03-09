const std = @import("std");

pub const SourcePath = struct {
    source_dir: std.fs.Dir,
    relative_path: []const u8,
};

pub fn resolveAbsolutePath(allocator: std.mem.Allocator, raw_path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(raw_path)) {
        return std.fs.path.resolve(allocator, &.{raw_path});
    }

    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    return std.fs.path.resolve(allocator, &.{ cwd, raw_path });
}

pub fn openSourcePath(absolute_path: []const u8) !SourcePath {
    const parent = std.fs.path.dirname(absolute_path) orelse return error.InvalidPath;
    const name = std.fs.path.basename(absolute_path);
    if (name.len == 0) return error.InvalidPath;

    const dir = try std.fs.openDirAbsolute(parent, .{});
    return .{
        .source_dir = dir,
        .relative_path = name,
    };
}
