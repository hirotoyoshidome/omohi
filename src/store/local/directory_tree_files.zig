const std = @import("std");

pub const StringList = std.array_list.Managed([]u8);

pub const Collection = struct {
    paths: StringList,
    skipped_non_regular: usize,

    // Initializes an empty collection that owns collected absolute file paths.
    pub fn init(allocator: std.mem.Allocator) Collection {
        return .{
            .paths = StringList.init(allocator),
            .skipped_non_regular = 0,
        };
    }
};

// Collects regular files below an absolute directory path and sorts them ascending.
pub fn collectAbsoluteRegularFiles(
    allocator: std.mem.Allocator,
    absolute_dir_path: []const u8,
) !Collection {
    var collection = Collection.init(allocator);
    errdefer freeCollection(allocator, &collection);

    try collectInto(allocator, absolute_dir_path, &collection);
    std.mem.sort([]u8, collection.paths.items, {}, lessThanPath);
    return collection;
}

// Releases the owned absolute file paths held in the collection.
pub fn freeCollection(allocator: std.mem.Allocator, collection: *Collection) void {
    for (collection.paths.items) |path| allocator.free(path);
    collection.paths.deinit();
}

// Recursively walks the absolute directory path and appends regular files.
fn collectInto(
    allocator: std.mem.Allocator,
    absolute_dir_path: []const u8,
    collection: *Collection,
) !void {
    var dir = try std.fs.openDirAbsolute(absolute_dir_path, .{ .iterate = true, .access_sub_paths = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        const child_path = try std.fs.path.resolve(allocator, &.{ absolute_dir_path, entry.name });
        errdefer allocator.free(child_path);

        switch (entry.kind) {
            .file => try collection.paths.append(child_path),
            .directory => {
                try collectInto(allocator, child_path, collection);
                allocator.free(child_path);
            },
            else => {
                collection.skipped_non_regular += 1;
                allocator.free(child_path);
            },
        }
    }
}

// Sorts collected absolute paths in ascending byte order.
fn lessThanPath(_: void, lhs: []u8, rhs: []u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

test "collectAbsoluteRegularFiles returns sorted regular files and counts non-regular entries" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var root = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer root.close();

    try root.makePath("nested");
    {
        var file = try root.createFile("nested/b.txt", .{});
        defer file.close();
        try file.writeAll("b");
    }
    {
        var file = try root.createFile("a.txt", .{});
        defer file.close();
        try file.writeAll("a");
    }
    try root.symLink("a.txt", "link.txt", .{});

    const absolute_root = try root.realpathAlloc(allocator, ".");
    defer allocator.free(absolute_root);

    var collection = try collectAbsoluteRegularFiles(allocator, absolute_root);
    defer freeCollection(allocator, &collection);

    try std.testing.expectEqual(@as(usize, 2), collection.paths.items.len);
    try std.testing.expectEqual(@as(usize, 1), collection.skipped_non_regular);
    try std.testing.expect(std.mem.endsWith(u8, collection.paths.items[0], "/a.txt"));
    try std.testing.expect(std.mem.endsWith(u8, collection.paths.items[1], "/nested/b.txt"));
}
