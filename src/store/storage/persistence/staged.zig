const std = @import("std");

const ContentEntry = @import("../../object/content_entry.zig").ContentEntry;
const PersistenceLayout = @import("../../object/persistence_layout.zig").PersistenceLayout;
const atomic_write = @import("../atomic_write.zig");
const constrained_types = @import("../../object/constrained_types.zig");

pub const EntryList = std.array_list.Managed(ContentEntry);

const max_entry_file_size = 1024 * 1024;
const max_staged_object_size = 64 * 1024 * 1024;

pub fn writeStagedEntry(
    allocator: std.mem.Allocator,
    persistence: PersistenceLayout,
    staged_file_id: []const u8,
    entry: ContentEntry,
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

fn parseStagedEntry(allocator: std.mem.Allocator, bytes: []const u8) !ContentEntry {
    var path_value: ?[]const u8 = null;
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
        } else if (std.mem.eql(u8, key, "contentHash")) {
            hash_value = value;
        }
    }

    const path = path_value orelse return error.InvalidStagedEntry;
    const stored_path = try allocator.dupe(u8, path);
    errdefer allocator.free(stored_path);
    const content_path = constrained_types.ContentPath.init(stored_path) catch return error.InvalidStagedEntry;

    const hash_str = hash_value orelse return error.InvalidStagedEntry;
    const content_hash = constrained_types.ContentHash.init(hash_str) catch return error.InvalidStagedEntry;

    return ContentEntry{
        .path = content_path,
        .content_hash = content_hash,
    };
}

fn formatStagedEntry(allocator: std.mem.Allocator, entry: ContentEntry) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "path={s}\ncontentHash={s}\n",
        .{ entry.path.asSlice(), entry.content_hash.asSlice() },
    );
}

fn ensureParentDirs(dir: std.fs.Dir, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| {
        if (parent.len == 0) return;
        try dir.makePath(parent);
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

    var persistence = PersistenceLayout.init(omohi_dir);
    try omohi_dir.makePath(persistence.stagedEntriesPath());
    try omohi_dir.makePath(persistence.stagedObjectsPath());

    var hash: [64]u8 = undefined;
    @memset(&hash, 'a');

    const entry_text = try std.fmt.allocPrint(allocator, "path=/objects/aa/{s}\ncontentHash={s}\n", .{ hash[0..], hash });
    defer allocator.free(entry_text);

    try writeStageEntryFile(allocator, omohi_dir, persistence.stagedEntriesPath(), "entry-1", entry_text);

    var entries = try loadStagedEntries(allocator, persistence);
    defer freeEntries(allocator, &entries);
    try std.testing.expectEqual(@as(usize, 1), entries.items.len);
    const expected_path = try std.fmt.allocPrint(allocator, "/objects/aa/{s}", .{hash});
    defer allocator.free(expected_path);
    try std.testing.expectEqualStrings(expected_path, entries.items[0].path.asSlice());
    try std.testing.expectEqualSlices(u8, &hash, entries.items[0].content_hash.asSlice());
}

test "writeStagedEntry persists staged entry via atomic write format" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    var persistence = PersistenceLayout.init(omohi_dir);

    var staged_id: [64]u8 = undefined;
    @memset(&staged_id, '1');
    var content_hash: [64]u8 = undefined;
    @memset(&content_hash, '2');

    const path_owned = try allocator.dupe(u8, "/objects/22/2222");
    defer allocator.free(path_owned);
    const entry = ContentEntry{
        .path = try constrained_types.ContentPath.init(path_owned),
        .content_hash = try constrained_types.ContentHash.init(&content_hash),
    };

    try writeStagedEntry(allocator, persistence, &staged_id, entry);

    const file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.stagedEntriesPath(), &staged_id });
    defer allocator.free(file_path);
    const stored = try omohi_dir.readFileAlloc(allocator, file_path, 1024);
    defer allocator.free(stored);
    try std.testing.expect(std.mem.indexOf(u8, stored, "path=/objects/22/2222") != null);
    try std.testing.expect(std.mem.indexOf(u8, stored, "contentHash=2222222222222222222222222222222222222222222222222222222222222222") != null);
}

test "copyFileToStagedObject copies source file content into staged objects" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var src_dir = try tmp.dir.makeOpenPath("src", .{ .iterate = true, .access_sub_paths = true });
    defer src_dir.close();
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    var persistence = PersistenceLayout.init(omohi_dir);

    var source = try src_dir.createFile("note.txt", .{});
    try source.writeAll("hello-stage");
    source.close();

    var hash: [64]u8 = undefined;
    @memset(&hash, '3');

    try copyFileToStagedObject(allocator, persistence, src_dir, "note.txt", &hash);

    const staged_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.stagedObjectsPath(), &hash });
    defer allocator.free(staged_path);
    const stored = try omohi_dir.readFileAlloc(allocator, staged_path, 1024);
    defer allocator.free(stored);
    try std.testing.expectEqualStrings("hello-stage", stored);
}

test "moveObjectsFromStage relocates staged object files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    var persistence = PersistenceLayout.init(omohi_dir);
    try omohi_dir.makePath(persistence.stagedObjectsPath());

    var hash: [64]u8 = undefined;
    @memset(&hash, 'b');

    const staged_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ persistence.stagedObjectsPath(), &hash });
    defer allocator.free(staged_path);

    var file = try omohi_dir.createFile(staged_path, .{});
    try file.writeAll("payload");
    file.close();

    try moveObjectsFromStage(allocator, persistence);

    const final_path = try persistence.objectsPath(allocator, &hash);
    defer allocator.free(final_path);
    const stored = try omohi_dir.readFileAlloc(allocator, final_path, 64);
    defer allocator.free(stored);
    try std.testing.expectEqualStrings("payload", stored);
    try std.testing.expectError(error.FileNotFound, omohi_dir.openFile(staged_path, .{}));
}

test "resetStaged recreates staged directories" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();

    var persistence = PersistenceLayout.init(omohi_dir);
    try omohi_dir.makePath(persistence.stagedEntriesPath());
    try omohi_dir.makePath(persistence.stagedObjectsPath());
    const filler = try std.fmt.allocPrint(std.testing.allocator, "{s}/junk", .{persistence.stagedEntriesPath()});
    defer std.testing.allocator.free(filler);
    var file = try omohi_dir.createFile(filler, .{});
    file.close();

    try resetStaged(persistence);

    try std.testing.expectError(
        error.FileNotFound,
        omohi_dir.openFile(filler, .{}),
    );
    var entries_dir = try omohi_dir.openDir(persistence.stagedEntriesPath(), .{});
    entries_dir.close();
    var objects_dir = try omohi_dir.openDir(persistence.stagedObjectsPath(), .{});
    objects_dir.close();
}
