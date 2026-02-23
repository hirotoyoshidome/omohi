const std = @import("std");

/// Describes the on-disk layout of the omohi persistence directory.
/// Keeps all directory paths in one place so other modules do not have
/// to reason about string literals.
pub const PersistenceLayout = struct {
    dir: std.fs.Dir,
    staged: Stage = .{},
    snapshots: PrefixedDirectory = .{ .base = "snapshots" },
    commits: PrefixedDirectory = .{ .base = "commits" },
    objects: PrefixedDirectory = .{ .base = "objects" },
    head_path: []const u8 = "HEAD",

    pub const Stage = struct {
        root: []const u8 = "staged",
        entries: []const u8 = "staged/entries",
        objects: []const u8 = "staged/objects",
    };

    pub const PrefixedDirectory = struct {
        base: []const u8,

        pub fn path(self: PrefixedDirectory, allocator: std.mem.Allocator, hex_id: []const u8) ![]u8 {
            return buildPrefixedPath(allocator, self.base, hex_id);
        }
    };

    pub fn init(dir: std.fs.Dir) PersistenceLayout {
        return .{ .dir = dir };
    }

    pub fn headPath(self: PersistenceLayout) []const u8 {
        return self.head_path;
    }

    pub fn stagedRoot(self: PersistenceLayout) []const u8 {
        return self.staged.root;
    }

    pub fn stagedEntriesPath(self: PersistenceLayout) []const u8 {
        return self.staged.entries;
    }

    pub fn stagedObjectsPath(self: PersistenceLayout) []const u8 {
        return self.staged.objects;
    }

    pub fn snapshotsPath(self: PersistenceLayout, allocator: std.mem.Allocator, snapshot_id: []const u8) ![]u8 {
        return self.snapshots.path(allocator, snapshot_id);
    }

    pub fn commitsPath(self: PersistenceLayout, allocator: std.mem.Allocator, commit_id: []const u8) ![]u8 {
        return self.commits.path(allocator, commit_id);
    }

    pub fn objectsPath(self: PersistenceLayout, allocator: std.mem.Allocator, hash: []const u8) ![]u8 {
        return self.objects.path(allocator, hash);
    }
};

fn buildPrefixedPath(
    allocator: std.mem.Allocator,
    base: []const u8,
    hex_id: []const u8,
) ![]u8 {
    if (hex_id.len != 64) return error.InvalidHexId;
    return std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{
        base,
        hex_id[0..2],
        hex_id,
    });
}

test "PersistenceLayout builds prefixed paths" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var layout = PersistenceLayout.init(tmp.dir);
    var id: [64]u8 = undefined;
    @memset(&id, 'a');

    const snapshot = try layout.snapshotsPath(std.testing.allocator, &id);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expect(std.mem.startsWith(u8, snapshot, "snapshots/aa/"));

    try std.testing.expectError(
        error.InvalidHexId,
        layout.snapshotsPath(std.testing.allocator, "short"),
    );
}
