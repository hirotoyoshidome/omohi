const std = @import("std");
const render_markdown = @import("docs/render_markdown.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const output = try render_markdown.renderCliMarkdown(allocator);
    defer allocator.free(output);

    try writeIfChanged(allocator, "docs/cli.md", output);
}

fn writeIfChanged(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) !void {
    const cwd = std.fs.cwd();
    try cwd.makePath("docs");

    const existing = cwd.readFileAlloc(allocator, path, 1024 * 1024 * 8) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    defer if (existing) |buf| allocator.free(buf);

    if (existing) |buf| {
        if (std.mem.eql(u8, buf, bytes)) return;
    }

    var file = try cwd.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}
