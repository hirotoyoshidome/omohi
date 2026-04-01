const std = @import("std");

const ContentEntry = @import("../object/content_entry.zig").ContentEntry;
const PersistenceLayout = @import("../object/persistence_layout.zig").PersistenceLayout;
const atomic_write = @import("../storage/atomic_write.zig");
const constrained_types = @import("../object/constrained_types.zig");
const hash = @import("../object/hash.zig");

pub const StagedEntry = struct {
    path: constrained_types.TrackedFilePath,
    tracked_file_id: constrained_types.TrackedFileId,
    content_hash: constrained_types.ContentHash,
};

pub const EntryList = std.array_list.Managed(StagedEntry);

pub const RawEntryInfo = struct {
    file_name: []u8,
    path: ?[]u8,
    content_hash: ?constrained_types.ContentHash,
};

pub const RawEntryList = std.array_list.Managed(RawEntryInfo);

const max_entry_file_size = 1024 * 1024;
const max_staged_object_size = 64 * 1024 * 1024;

pub fn writeStagedEntry(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    staged_file_id: []const u8,
    entry: StagedEntry,
) !void {
    _ = try constrained_types.StagedFileId.init(staged_file_id);

    const content = try formatStagedEntry(allocator, entry);
    defer allocator.free(content);

    const path = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}",
        .{ persistence.stagedEntriesPath(), staged_file_id },
    );
    defer allocator.free(path);

    try atomic_write.atomicWrite(allocator, persistence.dir, path, content);
}

pub fn copyFileToStagedObject(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    source_dir: std.fs.Dir,
    source_path: []const u8,
    content_hash: []const u8,
) !void {
    _ = try constrained_types.ContentHash.init(content_hash);

    var source_file = try source_dir.openFile(source_path, .{});
    defer source_file.close();

    const stat = try source_file.stat();
    const file_size = std.math.cast(usize, stat.size) orelse return error.FileTooLarge;
    const max_bytes = @max(file_size, @as(usize, 1));
    if (file_size > max_staged_object_size) return error.FileTooLarge;

    const bytes = try source_file.readToEndAlloc(allocator, max_bytes);
    defer allocator.free(bytes);

    const dest_path = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}",
        .{ persistence.stagedObjectsPath(), content_hash },
    );
    defer allocator.free(dest_path);

    try atomic_write.atomicWrite(allocator, persistence.dir, dest_path, bytes);
}

pub fn loadStagedEntries(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
) !EntryList {
    var entries_dir = persistence.dir.openDir(persistence.stagedEntriesPath(), .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return error.MissingStagedEntries,
        else => return err,
    };
    defer entries_dir.close();

    var entries = EntryList.init(allocator);
    errdefer freeEntries(allocator, &entries);

    var it = entries_dir.iterate();
    while (try it.next()) |dir_entry| {
        if (dir_entry.kind != .file) continue;

        const bytes = try entries_dir.readFileAlloc(allocator, dir_entry.name, max_entry_file_size);
        defer allocator.free(bytes);

        const entry = try parseStagedEntry(allocator, bytes);
        errdefer allocator.free(@constCast(entry.path.asSlice()));
        try entries.append(entry);
    }

    return entries;
}

pub fn freeEntries(allocator: std.mem.Allocator, entries: *EntryList) void {
    for (entries.items) |entry| allocator.free(@constCast(entry.path.asSlice()));
    entries.deinit();
}

pub fn listRawEntries(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
) !RawEntryList {
    var entries_dir = persistence.dir.openDir(persistence.stagedEntriesPath(), .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return error.MissingStagedEntries,
        else => return err,
    };
    defer entries_dir.close();

    var entries = RawEntryList.init(allocator);
    errdefer freeRawEntries(allocator, &entries);

    var it = entries_dir.iterate();
    while (try it.next()) |dir_entry| {
        if (dir_entry.kind != .file) continue;

        const file_name = try allocator.dupe(u8, dir_entry.name);
        errdefer allocator.free(file_name);

        const bytes = try entries_dir.readFileAlloc(allocator, dir_entry.name, max_entry_file_size);
        defer allocator.free(bytes);

        try entries.append(.{
            .file_name = file_name,
            .path = try extractPathValueOwned(allocator, bytes),
            .content_hash = extractContentHashValue(bytes),
        });
    }

    return entries;
}

pub fn freeRawEntries(allocator: std.mem.Allocator, entries: *RawEntryList) void {
    for (entries.items) |entry| {
        allocator.free(entry.file_name);
        if (entry.path) |path| allocator.free(path);
    }
    entries.deinit();
}

pub fn findByPath(entries: []const StagedEntry, absolute_path: []const u8) ?StagedEntry {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.path.asSlice(), absolute_path)) return entry;
    }
    return null;
}

pub fn containsPath(entries: []const StagedEntry, absolute_path: []const u8) bool {
    return findByPath(entries, absolute_path) != null;
}

pub fn stagedFileIdForEntry(entry: StagedEntry) [64]u8 {
    return hash.stagedFileIdFrom(entry.path.asSlice(), entry.content_hash.asSlice());
}

pub fn ensureObjectsExistForEntries(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    entries: []const StagedEntry,
) !void {
    for (entries) |entry| {
        const hash_value = entry.content_hash.asSlice();

        const staged_path = try std.fmt.allocPrint(
            allocator,
            "{s}/{s}",
            .{ persistence.stagedObjectsPath(), hash_value },
        );
        defer allocator.free(staged_path);

        persistence.dir.access(staged_path, .{}) catch |staged_err| switch (staged_err) {
            error.FileNotFound => {
                const object_path = try persistence.objectsPath(allocator, hash_value);
                defer allocator.free(object_path);

                persistence.dir.access(object_path, .{}) catch |object_err| switch (object_err) {
                    error.FileNotFound => return error.StagedObjectMissing,
                    else => return object_err,
                };
            },
            else => return staged_err,
        };
    }
}

pub fn moveObjectsFromStage(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
) !void {
    var objects_dir = persistence.dir.openDir(persistence.stagedObjectsPath(), .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return error.MissingStagedObjects,
        else => return err,
    };
    defer objects_dir.close();

    var it = objects_dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (entry.name.len != 64) return error.InvalidStagedEntry;

        const from_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.stagedObjectsPath(), entry.name });
        defer allocator.free(from_path);

        const dest_path = try persistence.objectsPath(allocator, entry.name);
        defer allocator.free(dest_path);

        try ensureParentDirs(persistence.dir, dest_path);

        persistence.dir.rename(from_path, dest_path) catch |err| switch (err) {
            error.PathAlreadyExists => {
                persistence.dir.deleteFile(from_path) catch {};
            },
            error.FileNotFound => return error.StagedObjectMissing,
            else => return err,
        };
        try syncParentDir(persistence.dir, dest_path);
    }
}

pub fn resetStaged(persistence: PersistenceLayout) !void {
    var has_staged = true;
    persistence.dir.access(persistence.stagedRoot(), .{}) catch |err| switch (err) {
        error.FileNotFound => has_staged = false,
        else => return err,
    };
    if (has_staged) try persistence.dir.deleteTree(persistence.stagedRoot());
    try persistence.dir.makePath(persistence.stagedEntriesPath());
    try persistence.dir.makePath(persistence.stagedObjectsPath());
}

pub fn freeSnapshotEntries(allocator: std.mem.Allocator, entries: *std.array_list.Managed(ContentEntry)) void {
    for (entries.items) |entry| allocator.free(@constCast(entry.path.asSlice()));
    entries.deinit();
}

pub fn snapshotEntriesFromStaged(
    allocator: std.mem.Allocator,
    entries: []const StagedEntry,
) !std.array_list.Managed(ContentEntry) {
    var out = std.array_list.Managed(ContentEntry).init(allocator);
    errdefer freeSnapshotEntries(allocator, &out);

    for (entries) |entry| {
        const owned_path = try allocator.dupe(u8, entry.path.asSlice());
        errdefer allocator.free(owned_path);
        try out.append(.{
            .path = try constrained_types.TrackedFilePath.init(owned_path),
            .content_hash = entry.content_hash,
        });
    }

    return out;
}

fn parseStagedEntry(allocator: std.mem.Allocator, bytes: []const u8) !StagedEntry {
    var path_value: ?[]const u8 = null;
    var tracked_file_id_value: ?[]const u8 = null;
    var hash_value: ?[]const u8 = null;

    var iter = std.mem.splitScalar(u8, bytes, '\n');
    while (iter.next()) |line_raw| {
        const line = std.mem.trim(u8, std.mem.trimRight(u8, line_raw, "\r"), " \t");
        if (line.len == 0 or line[0] == '#') continue;
        const idx = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trimRight(u8, line[0..idx], " ");
        const value = std.mem.trim(u8, std.mem.trimRight(u8, line[idx + 1 ..], "\r"), " \t");

        if (std.mem.eql(u8, key, "path")) {
            path_value = value;
        } else if (std.mem.eql(u8, key, "trackedFileId")) {
            tracked_file_id_value = value;
        } else if (std.mem.eql(u8, key, "contentHash")) {
            hash_value = value;
        }
    }

    const path = path_value orelse return error.InvalidStagedEntry;
    const stored_path = try allocator.dupe(u8, path);
    errdefer allocator.free(stored_path);
    const tracked_path = constrained_types.TrackedFilePath.init(stored_path) catch return error.InvalidStagedEntry;

    const tracked_file_id_raw = tracked_file_id_value orelse return error.InvalidStagedEntry;
    const tracked_file_id = constrained_types.TrackedFileId.init(tracked_file_id_raw) catch return error.InvalidStagedEntry;

    const hash_str = hash_value orelse return error.InvalidStagedEntry;
    const content_hash = constrained_types.ContentHash.init(hash_str) catch return error.InvalidStagedEntry;

    return StagedEntry{
        .path = tracked_path,
        .tracked_file_id = tracked_file_id,
        .content_hash = content_hash,
    };
}

fn extractPathValueOwned(allocator: std.mem.Allocator, bytes: []const u8) !?[]u8 {
    const raw_path = propertyValue(bytes, "path") orelse return null;
    const owned = try allocator.dupe(u8, raw_path);
    errdefer allocator.free(owned);
    _ = constrained_types.TrackedFilePath.init(owned) catch {
        allocator.free(owned);
        return null;
    };
    return owned;
}

fn extractContentHashValue(bytes: []const u8) ?constrained_types.ContentHash {
    const raw_hash = propertyValue(bytes, "contentHash") orelse return null;
    return constrained_types.ContentHash.init(raw_hash) catch null;
}

fn propertyValue(bytes: []const u8, key: []const u8) ?[]const u8 {
    var iter = std.mem.splitScalar(u8, bytes, '\n');
    while (iter.next()) |line_raw| {
        const line = std.mem.trim(u8, std.mem.trimRight(u8, line_raw, "\r"), " \t");
        if (line.len == 0 or line[0] == '#') continue;
        const idx = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const candidate_key = std.mem.trimRight(u8, line[0..idx], " ");
        if (!std.mem.eql(u8, candidate_key, key)) continue;
        return std.mem.trim(u8, std.mem.trimRight(u8, line[idx + 1 ..], "\r"), " \t");
    }
    return null;
}

fn formatStagedEntry(allocator: std.mem.Allocator, entry: StagedEntry) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "path={s}\ntrackedFileId={s}\ncontentHash={s}\n",
        .{ entry.path.asSlice(), entry.tracked_file_id.asSlice(), entry.content_hash.asSlice() },
    );
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

fn syncDir(dir: std.fs.Dir) !void {
    const rc = std.posix.system.fsync(dir.fd);
    switch (std.posix.errno(rc)) {
        .SUCCESS, .BADF, .INVAL, .ROFS => return,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}

fn writeStageEntryFile(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    entries_path: []const u8,
    name: []const u8,
    content: []const u8,
) !void {
    const entry_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ entries_path, name });
    defer allocator.free(entry_path);
    var file = try dir.createFile(entry_path, .{});
    defer file.close();
    try file.writeAll(content);
}

test "loadStagedEntries parses entries and frees allocated paths" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    const persistence = PersistenceLayout.init(omohi_dir);
    try omohi_dir.makePath(persistence.stagedEntriesPath());

    var hash_value: [64]u8 = undefined;
    @memset(&hash_value, 'a');
    const entry_text = try std.fmt.allocPrint(
        allocator,
        "path=/tmp/example.txt\ntrackedFileId=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\ncontentHash={s}\n",
        .{hash_value},
    );
    defer allocator.free(entry_text);

    try writeStageEntryFile(allocator, omohi_dir, persistence.stagedEntriesPath(), "entry", entry_text);

    var entries = try loadStagedEntries(allocator, persistence);
    defer freeEntries(allocator, &entries);

    try std.testing.expectEqual(@as(usize, 1), entries.items.len);
    try std.testing.expectEqualStrings("/tmp/example.txt", entries.items[0].path.asSlice());
    try std.testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", entries.items[0].tracked_file_id.asSlice());
    try std.testing.expectEqualStrings(&hash_value, entries.items[0].content_hash.asSlice());
}

test "writeStagedEntry persists staged entry via atomic write format" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    const persistence = PersistenceLayout.init(omohi_dir);
    try omohi_dir.makePath(persistence.stagedEntriesPath());

    var staged_id: [64]u8 = undefined;
    @memset(&staged_id, '1');

    const entry = StagedEntry{
        .path = try constrained_types.TrackedFilePath.init(try allocator.dupe(u8, "/tmp/file.txt")),
        .tracked_file_id = try constrained_types.TrackedFileId.init("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
        .content_hash = try constrained_types.ContentHash.init("2222222222222222222222222222222222222222222222222222222222222222"),
    };
    defer allocator.free(@constCast(entry.path.asSlice()));

    try writeStagedEntry(allocator, persistence, &staged_id, entry);

    const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.stagedEntriesPath(), staged_id });
    defer allocator.free(path);
    const stored = try omohi_dir.readFileAlloc(allocator, path, 1024);
    defer allocator.free(stored);

    try std.testing.expect(std.mem.indexOf(u8, stored, "path=/tmp/file.txt") != null);
    try std.testing.expect(std.mem.indexOf(u8, stored, "trackedFileId=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb") != null);
    try std.testing.expect(std.mem.indexOf(u8, stored, "contentHash=2222222222222222222222222222222222222222222222222222222222222222") != null);
}

test "ensureObjectsExistForEntries accepts staged or committed objects and rejects missing hashes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    const persistence = PersistenceLayout.init(omohi_dir);
    try omohi_dir.makePath(persistence.stagedObjectsPath());
    try omohi_dir.makePath("objects/bb");

    {
        var staged_file = try omohi_dir.createFile("staged/objects/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", .{});
        defer staged_file.close();
        try staged_file.writeAll("stage");
    }
    {
        var committed_file = try omohi_dir.createFile("objects/bb/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", .{});
        defer committed_file.close();
        try committed_file.writeAll("committed");
    }

    const staged_entry = StagedEntry{
        .path = try constrained_types.TrackedFilePath.init(try allocator.dupe(u8, "/tmp/a.txt")),
        .tracked_file_id = try constrained_types.TrackedFileId.init("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
        .content_hash = try constrained_types.ContentHash.init("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    };
    const committed_entry = StagedEntry{
        .path = try constrained_types.TrackedFilePath.init(try allocator.dupe(u8, "/tmp/b.txt")),
        .tracked_file_id = try constrained_types.TrackedFileId.init("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
        .content_hash = try constrained_types.ContentHash.init("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
    };
    const missing_entry = StagedEntry{
        .path = try constrained_types.TrackedFilePath.init(try allocator.dupe(u8, "/tmp/c.txt")),
        .tracked_file_id = try constrained_types.TrackedFileId.init("cccccccccccccccccccccccccccccccc"),
        .content_hash = try constrained_types.ContentHash.init("cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"),
    };
    defer allocator.free(@constCast(staged_entry.path.asSlice()));
    defer allocator.free(@constCast(committed_entry.path.asSlice()));
    defer allocator.free(@constCast(missing_entry.path.asSlice()));

    try ensureObjectsExistForEntries(allocator, persistence, &.{ staged_entry, committed_entry });
    try std.testing.expectError(error.StagedObjectMissing, ensureObjectsExistForEntries(allocator, persistence, &.{missing_entry}));
}
