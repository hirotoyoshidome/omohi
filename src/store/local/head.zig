const std = @import("std");

const atomic_write = @import("../storage/atomic_write.zig");
const PersistenceLayout = @import("../object/persistence_layout.zig").PersistenceLayout;

pub fn writeHead(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    commit_id: []const u8,
) !void {
    const content = try formatHeadFile(allocator, commit_id);
    defer allocator.free(content);
    try atomic_write.atomicWrite(allocator, persistence.dir, persistence.headPath(), content);
}

fn formatHeadFile(allocator: std.mem.Allocator, commit_id: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}\n", .{commit_id});
}

test "writeHead replaces head file with new commit id" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true });
    defer omohi_dir.close();

    var persistence = PersistenceLayout.init(omohi_dir);
    var first: [64]u8 = undefined;
    @memset(&first, 'a');
    var second: [64]u8 = undefined;
    @memset(&second, 'b');

    try writeHead(allocator, persistence, &first);
    try writeHead(allocator, persistence, &second);

    const content = try omohi_dir.readFileAlloc(allocator, persistence.headPath(), 256);
    defer allocator.free(content);
    try std.testing.expectEqualStrings("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n", content);
}
