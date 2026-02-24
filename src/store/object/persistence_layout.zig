const std = @import("std");

/// Describes the on-disk layout of the omohi persistence directory.
/// Keeps all directory paths in one place so other modules do not have
/// to reason about string literals.
pub const PersistenceLayout = struct {
    dir: std.fs.Dir,
    staged: Stage = .{},
    data: Data = .{},
    tracked_path: []const u8 = "tracked",
    snapshots: PrefixedDirectory = .{ .base = "snapshots" },
    commits: PrefixedDirectory = .{ .base = "commits" },
    objects: PrefixedDirectory = .{ .base = "objects" },
    journal_path: []const u8 = "journal",
    version_path: []const u8 = "VERSION",
    head_path: []const u8 = "HEAD",

    pub const Stage = struct {
        root: []const u8 = "staged",
        entries: []const u8 = "staged/entries",
        objects: []const u8 = "staged/objects",
    };

    pub const Data = struct {
        root: []const u8 = "data",
        tags: []const u8 = "data/tags",
        commit_tags: PrefixedDirectory = .{ .base = "data/commit-tags" },
    };

    pub const PrefixedDirectory = struct {
        base: []const u8,

        /// Builds a prefixed path using the leading two characters of the hex id.
        /// Memory: owned (caller must free)
        /// Errors: error{InvalidHexId,OutOfMemory}
        pub fn path(self: PrefixedDirectory, allocator: std.mem.Allocator, hex_id: []const u8) ![]u8 {
            return buildPrefixedPath(allocator, self.base, hex_id, .normal);
        }

        /// Builds a prefixed trash path using the leading two characters of the hex id.
        /// Memory: owned (caller must free)
        /// Errors: error{InvalidHexId,OutOfMemory}
        pub fn trashPath(self: PrefixedDirectory, allocator: std.mem.Allocator, hex_id: []const u8) ![]u8 {
            return buildPrefixedPath(allocator, self.base, hex_id, .trash);
        }
    };

    /// Creates a new layout rooted at the provided directory handle.
    /// Memory: borrowed (dir is owned by the caller)
    /// Errors: none
    pub fn init(dir: std.fs.Dir) PersistenceLayout {
        return .{ .dir = dir };
    }

    /// Returns the relative path to the HEAD file.
    /// Memory: borrowed
    /// Errors: none
    pub fn headPath(self: PersistenceLayout) []const u8 {
        return self.head_path;
    }

    /// Returns the relative path to the tracked directory.
    /// Memory: borrowed
    /// Errors: none
    pub fn trackedPath(self: PersistenceLayout) []const u8 {
        return self.tracked_path;
    }

    /// Returns the relative path to deleted tracked entries directory.
    /// Memory: borrowed
    /// Errors: none
    pub fn trackedTrashPath(self: PersistenceLayout) []const u8 {
        return trashPath(self.tracked_path);
    }

    /// Returns the relative path to the journal directory.
    /// Memory: borrowed
    /// Errors: none
    pub fn journalPath(self: PersistenceLayout) []const u8 {
        return self.journal_path;
    }

    /// Returns the relative path to the VERSION file.
    /// Memory: borrowed
    /// Errors: none
    pub fn versionPath(self: PersistenceLayout) []const u8 {
        return self.version_path;
    }

    /// Returns the relative path to the staged directory root.
    /// Memory: borrowed
    /// Errors: none
    pub fn stagedRoot(self: PersistenceLayout) []const u8 {
        return self.staged.root;
    }

    /// Returns the relative path to staged entries.
    /// Memory: borrowed
    /// Errors: none
    pub fn stagedEntriesPath(self: PersistenceLayout) []const u8 {
        return self.staged.entries;
    }

    /// Returns the relative path to deleted staged entries.
    /// Memory: borrowed
    /// Errors: none
    pub fn stagedEntriesTrashPath(self: PersistenceLayout) []const u8 {
        return trashPath(self.staged.entries);
    }

    /// Returns the relative path to staged objects.
    /// Memory: borrowed
    /// Errors: none
    pub fn stagedObjectsPath(self: PersistenceLayout) []const u8 {
        return self.staged.objects;
    }

    /// Returns the relative path to deleted staged objects.
    /// Memory: borrowed
    /// Errors: none
    pub fn stagedObjectsTrashPath(self: PersistenceLayout) []const u8 {
        return trashPath(self.staged.objects);
    }

    /// Returns the relative path to data root.
    /// Memory: borrowed
    /// Errors: none
    pub fn dataRoot(self: PersistenceLayout) []const u8 {
        return self.data.root;
    }

    /// Returns the relative path to tags directory.
    /// Memory: borrowed
    /// Errors: none
    pub fn dataTagsPath(self: PersistenceLayout) []const u8 {
        return self.data.tags;
    }

    /// Returns the relative path to deleted tags directory.
    /// Memory: borrowed
    /// Errors: none
    pub fn dataTagsTrashPath(self: PersistenceLayout) []const u8 {
        return trashPath(self.data.tags);
    }

    /// Builds the prefixed path for commit tags data.
    /// Memory: owned (caller must free)
    /// Errors: error{InvalidHexId,OutOfMemory}
    pub fn commitTagsPath(self: PersistenceLayout, allocator: std.mem.Allocator, commit_id: []const u8) ![]u8 {
        return self.data.commit_tags.path(allocator, commit_id);
    }

    /// Builds the prefixed path for deleted commit tags data.
    /// Memory: owned (caller must free)
    /// Errors: error{InvalidHexId,OutOfMemory}
    pub fn commitTagsTrashPath(self: PersistenceLayout, allocator: std.mem.Allocator, commit_id: []const u8) ![]u8 {
        return self.data.commit_tags.trashPath(allocator, commit_id);
    }

    /// Builds the prefixed path for snapshots.
    /// Memory: owned (caller must free)
    /// Errors: error{InvalidHexId,OutOfMemory}
    pub fn snapshotsPath(self: PersistenceLayout, allocator: std.mem.Allocator, snapshot_id: []const u8) ![]u8 {
        return self.snapshots.path(allocator, snapshot_id);
    }

    /// Builds the prefixed path for commits.
    /// Memory: owned (caller must free)
    /// Errors: error{InvalidHexId,OutOfMemory}
    pub fn commitsPath(self: PersistenceLayout, allocator: std.mem.Allocator, commit_id: []const u8) ![]u8 {
        return self.commits.path(allocator, commit_id);
    }

    /// Builds the prefixed path for objects.
    /// Memory: owned (caller must free)
    /// Errors: error{InvalidHexId,OutOfMemory}
    pub fn objectsPath(self: PersistenceLayout, allocator: std.mem.Allocator, hash: []const u8) ![]u8 {
        return self.objects.path(allocator, hash);
    }

    /// Builds the prefixed path for deleted objects.
    /// Memory: owned (caller must free)
    /// Errors: error{InvalidHexId,OutOfMemory}
    pub fn objectsTrashPath(self: PersistenceLayout, allocator: std.mem.Allocator, hash: []const u8) ![]u8 {
        return self.objects.trashPath(allocator, hash);
    }
};

fn trashPath(comptime base: []const u8) []const u8 {
    return base ++ "/.trash";
}

fn buildPrefixedPath(
    allocator: std.mem.Allocator,
    base: []const u8,
    hex_id: []const u8,
    mode: PrefixedPathMode,
) ![]u8 {
    if (hex_id.len != 64) return error.InvalidHexId;
    return switch (mode) {
        .normal => std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{
            base,
            hex_id[0..2],
            hex_id,
        }),
        .trash => std.fmt.allocPrint(allocator, "{s}/.trash/{s}/{s}", .{
            base,
            hex_id[0..2],
            hex_id,
        }),
    };
}

const PrefixedPathMode = enum {
    normal,
    trash,
};

test "PersistenceLayout builds prefixed paths" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var layout = PersistenceLayout.init(tmp.dir);
    var id: [64]u8 = undefined;
    @memset(&id, 'a');

    const snapshot = try layout.snapshotsPath(std.testing.allocator, &id);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expect(std.mem.startsWith(u8, snapshot, "snapshots/aa/"));

    const commit_tags = try layout.commitTagsPath(std.testing.allocator, &id);
    defer std.testing.allocator.free(commit_tags);
    try std.testing.expect(std.mem.startsWith(u8, commit_tags, "data/commit-tags/aa/"));

    const commit_tags_trash = try layout.commitTagsTrashPath(std.testing.allocator, &id);
    defer std.testing.allocator.free(commit_tags_trash);
    try std.testing.expect(std.mem.startsWith(u8, commit_tags_trash, "data/commit-tags/.trash/aa/"));

    const objects_trash = try layout.objectsTrashPath(std.testing.allocator, &id);
    defer std.testing.allocator.free(objects_trash);
    try std.testing.expect(std.mem.startsWith(u8, objects_trash, "objects/.trash/aa/"));

    try std.testing.expectEqualStrings("tracked/.trash", layout.trackedTrashPath());
    try std.testing.expectEqualStrings("staged/entries/.trash", layout.stagedEntriesTrashPath());
    try std.testing.expectEqualStrings("staged/objects/.trash", layout.stagedObjectsTrashPath());
    try std.testing.expectEqualStrings("data/tags/.trash", layout.dataTagsTrashPath());

    try std.testing.expectError(
        error.InvalidHexId,
        layout.snapshotsPath(std.testing.allocator, "short"),
    );
}
