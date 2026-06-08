const std = @import("std");

const constrained_types = @import("../object/constrained_types.zig");
const version_guard = @import("../storage/version_guard.zig");

const backup_root = ".omohi";
const temp_suffix_prefix = ".restore-tmp-";
const rollback_suffix_prefix = ".restore-rollback-";
const max_tracked_file_size = 16 * 1024;

/// Carries normalized restore paths and restore safety options.
pub const RestoreOptions = struct {
    store_path: []const u8,
    archive_path: []const u8,
    replace_existing: bool,
    max_size: u64,
};

/// Reports a completed restore and owns rollback_path when present.
pub const RestoreResult = struct {
    entry_count: usize,
    missing_tracked_count: usize,
    rollback_path: ?[]u8,
};

/// Releases optional owned memory in a restore result.
/// Memory: frees allocator-backed fields in result
/// Lifetime: result must not be used after this call
/// Errors: none
/// Caller responsibilities: call once for results returned by restoreBackup
pub fn freeRestoreResult(allocator: std.mem.Allocator, result: *RestoreResult) void {
    if (result.rollback_path) |path| allocator.free(path);
    result.* = undefined;
}

/// Restores a gzip-compressed tar backup into the user-level store directory.
/// Memory: borrowed options, returned rollback path is allocator-owned
/// Lifetime: rollback path remains valid until freeRestoreResult
/// Errors: validation, archive, version, size, and filesystem failures
/// Caller responsibilities: pass absolute normalized store and archive paths
pub fn restoreBackup(
    allocator: std.mem.Allocator,
    options: RestoreOptions,
) !RestoreResult {
    if (options.max_size == 0) return error.RestoreTooLarge;

    const parent_path = std.fs.path.dirname(options.store_path) orelse return error.InvalidPath;
    const store_name = std.fs.path.basename(options.store_path);
    if (store_name.len == 0) return error.InvalidPath;

    var parent_dir = try std.fs.openDirAbsolute(parent_path, .{ .iterate = true, .access_sub_paths = true });
    defer parent_dir.close();

    try validateExistingStore(parent_dir, store_name, options.replace_existing);
    {
        var archive = try std.fs.openFileAbsolute(options.archive_path, .{});
        defer archive.close();
        const archive_stat = try archive.stat();
        if (archive_stat.size > options.max_size) return error.RestoreTooLarge;
    }

    const temp_name = try makeUniqueSiblingName(allocator, parent_dir, store_name, temp_suffix_prefix);
    defer allocator.free(temp_name);
    try parent_dir.makeDir(temp_name);
    errdefer parent_dir.deleteTree(temp_name) catch {};

    var temp_dir = try parent_dir.openDir(temp_name, .{ .iterate = true, .access_sub_paths = true });
    defer temp_dir.close();

    const entry_count = extractArchive(temp_dir, options.archive_path, options.max_size) catch |err| switch (err) {
        error.RestoreTooLarge,
        error.UnsupportedRestoreEntry,
        error.InvalidRestoreArchive,
        error.OutOfMemory,
        error.FileNotFound,
        error.AccessDenied,
        error.NoSpaceLeft,
        error.FileTooBig,
        error.NameTooLong,
        error.PathAlreadyExists,
        => return err,
        else => if (isArchiveReadError(err)) return error.InvalidRestoreArchive else return err,
    };
    try validateRestoredStore(allocator, temp_dir);
    const missing_count = try countMissingTracked(allocator, temp_dir);
    try syncDir(temp_dir);

    const rollback_name = if (options.replace_existing and try pathExists(parent_dir, store_name))
        try makeUniqueSiblingName(allocator, parent_dir, store_name, rollback_suffix_prefix)
    else
        null;
    errdefer if (rollback_name) |name| allocator.free(name);
    const rollback_path = if (rollback_name) |name|
        try std.fs.path.join(allocator, &.{ parent_path, name })
    else
        null;
    errdefer if (rollback_path) |path| allocator.free(path);

    if (rollback_name) |name| {
        try parent_dir.rename(store_name, name);
        errdefer parent_dir.rename(name, store_name) catch {};
    } else if (try pathExists(parent_dir, store_name)) {
        try parent_dir.deleteDir(store_name);
    }

    try parent_dir.rename(temp_name, store_name);
    try syncDir(parent_dir);

    if (rollback_name) |name| allocator.free(name);

    return .{
        .entry_count = entry_count,
        .missing_tracked_count = missing_count,
        .rollback_path = rollback_path,
    };
}

// Rejects non-empty existing stores unless explicit replacement was requested.
fn validateExistingStore(parent_dir: std.fs.Dir, store_name: []const u8, replace_existing: bool) !void {
    var store_dir = parent_dir.openDir(store_name, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer store_dir.close();

    if (!try isDirEmpty(store_dir) and !replace_existing) return error.RestoreTargetExists;
}

// Extracts one backup archive while validating its tar entry paths.
fn extractArchive(
    temp_dir: std.fs.Dir,
    archive_path: []const u8,
    max_size: u64,
) !usize {
    var archive = try std.fs.openFileAbsolute(archive_path, .{});
    defer archive.close();

    var file_buffer: [32 * 1024]u8 = undefined;
    var file_reader = archive.reader(&file_buffer);
    var inflate_buffer: [std.compress.flate.max_window_len]u8 = undefined;
    var inflater: std.compress.flate.Decompress = .init(&file_reader.interface, .gzip, &inflate_buffer);

    var file_name_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var link_name_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var tar_iter: std.tar.Iterator = .init(&inflater.reader, .{
        .file_name_buffer = &file_name_buffer,
        .link_name_buffer = &link_name_buffer,
    });

    var entry_count: usize = 0;
    var extracted_bytes: u64 = 0;
    while (try tar_iter.next()) |entry| {
        const relative_path = try validateArchiveEntryPath(entry);
        if (relative_path.len == 0) continue;

        switch (entry.kind) {
            .directory => try temp_dir.makePath(relative_path),
            .file => {
                extracted_bytes = try addSize(extracted_bytes, entry.size);
                if (extracted_bytes > max_size) return error.RestoreTooLarge;
                try writeExtractedFile(temp_dir, relative_path, &tar_iter, entry);
            },
            .sym_link => return error.UnsupportedRestoreEntry,
        }
        entry_count += 1;
    }

    return entry_count;
}

// Validates backup paths and returns the path relative to the store root.
fn validateArchiveEntryPath(entry: std.tar.Iterator.File) ![]const u8 {
    if (entry.name.len == 0) return error.InvalidRestoreArchive;
    if (entry.name[0] == '/') return error.InvalidRestoreArchive;
    if (std.mem.eql(u8, entry.name, backup_root)) {
        if (entry.kind == .directory) return "";
        return error.InvalidRestoreArchive;
    }
    if (!std.mem.startsWith(u8, entry.name, backup_root ++ "/")) return error.InvalidRestoreArchive;

    const relative_path = entry.name[backup_root.len + 1 ..];
    if (relative_path.len == 0) return error.InvalidRestoreArchive;
    if (std.mem.indexOfScalar(u8, relative_path, '\\') != null) return error.InvalidRestoreArchive;
    if (std.mem.eql(u8, relative_path, "LOCK")) return error.UnsupportedRestoreEntry;

    var components = std.mem.splitScalar(u8, relative_path, '/');
    while (components.next()) |component| {
        if (component.len == 0) return error.InvalidRestoreArchive;
        if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return error.InvalidRestoreArchive;
        if (std.mem.eql(u8, component, ".trash")) return error.UnsupportedRestoreEntry;
    }
    return relative_path;
}

// Streams one tar file entry into the temporary store directory and fsyncs it.
fn writeExtractedFile(
    temp_dir: std.fs.Dir,
    path: []const u8,
    tar_iter: *std.tar.Iterator,
    entry: std.tar.Iterator.File,
) !void {
    try ensureParentDirs(temp_dir, path);
    var file = try temp_dir.createFile(path, .{ .exclusive = true });
    errdefer file.close();

    var out_buffer: [32 * 1024]u8 = undefined;
    var writer = file.writer(&out_buffer);
    try tar_iter.streamRemaining(entry, &writer.interface);
    try writer.interface.flush();
    try file.sync();
    file.close();
    try syncParentDir(temp_dir, path);
}

// Validates restored metadata through the existing version guard.
fn validateRestoredStore(allocator: std.mem.Allocator, temp_dir: std.fs.Dir) !void {
    try version_guard.ensureStoreVersion(allocator, temp_dir);
}

// Counts tracked records whose absolute paths do not exist in this environment.
fn countMissingTracked(allocator: std.mem.Allocator, temp_dir: std.fs.Dir) !usize {
    var tracked_dir = temp_dir.openDir("tracked", .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return 0,
        else => return err,
    };
    defer tracked_dir.close();

    var missing: usize = 0;
    var it = tracked_dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        _ = constrained_types.TrackedFileId.init(entry.name) catch return error.InvalidRestoreArchive;

        const bytes = try tracked_dir.readFileAlloc(allocator, entry.name, max_tracked_file_size);
        defer allocator.free(bytes);
        const path = std.mem.trim(u8, std.mem.trimRight(u8, bytes, "\r\n"), " \t");
        _ = constrained_types.TrackedFilePath.init(path) catch return error.InvalidRestoreArchive;

        var target = std.fs.openFileAbsolute(path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                missing += 1;
                continue;
            },
            else => return err,
        };
        target.close();
    }
    return missing;
}

// Reports whether the opened directory has no entries.
fn isDirEmpty(dir: std.fs.Dir) !bool {
    var it = dir.iterate();
    while (try it.next()) |_| return false;
    return true;
}

// Reports whether a path exists below the parent directory.
fn pathExists(parent_dir: std.fs.Dir, name: []const u8) !bool {
    parent_dir.access(name, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}

// Builds a unique sibling directory name for temp and rollback directories.
fn makeUniqueSiblingName(
    allocator: std.mem.Allocator,
    parent_dir: std.fs.Dir,
    store_name: []const u8,
    suffix_prefix: []const u8,
) ![]u8 {
    var attempts: usize = 0;
    while (attempts < 32) : (attempts += 1) {
        var random: [8]u8 = undefined;
        std.crypto.random.bytes(&random);
        var hex: [random.len * 2]u8 = undefined;
        encodeHexLower(&hex, &random);
        const name = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ store_name, suffix_prefix, &hex });
        if (!try pathExists(parent_dir, name)) return name;
        allocator.free(name);
    }
    return error.PathAlreadyExists;
}

// Adds file sizes with overflow protection.
fn addSize(lhs: u64, rhs: u64) !u64 {
    return std.math.add(u64, lhs, rhs) catch return error.RestoreTooLarge;
}

// Reports gzip/tar reader failures that mean the archive is not a valid backup.
fn isArchiveReadError(err: anyerror) bool {
    const name = @errorName(err);
    if (std.mem.startsWith(u8, name, "Tar")) return true;
    return err == error.BadMagic or
        err == error.EndOfStream or
        err == error.ReadFailed or
        err == error.InvalidStoredSize or
        err == error.InvalidBlockType or
        err == error.InvalidDynamicBlockHeader or
        err == error.WrongChecksum;
}

// Ensures that the parent directories for a relative path exist.
fn ensureParentDirs(dir: std.fs.Dir, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| {
        if (parent.len == 0) return;
        try dir.makePath(parent);
    }
}

// Fsyncs the parent directory for one relative path.
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

// Fsyncs a directory and tolerates platforms that reject directory fsync.
fn syncDir(dir: std.fs.Dir) !void {
    const rc = std.posix.system.fsync(dir.fd);
    switch (std.posix.errno(rc)) {
        .SUCCESS, .BADF, .INVAL, .ROFS => return,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}

// Encodes bytes into lowercase hexadecimal characters.
fn encodeHexLower(dest: []u8, source: []const u8) void {
    const alphabet = "0123456789abcdef";
    var idx: usize = 0;
    for (source) |byte| {
        dest[idx] = alphabet[@as(usize, byte >> 4)];
        dest[idx + 1] = alphabet[@as(usize, byte & 0x0f)];
        idx += 2;
    }
}

test "restoreBackup restores archive created by backup writer" {
    const backup = @import("./backup.zig");

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("source/.omohi", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();

    try source_dir.writeFile(.{ .sub_path = "VERSION", .data = "1\n" });
    try source_dir.makePath("tracked");
    const root_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);
    const tracked_path = try std.fmt.allocPrint(allocator, "{s}/missing-target.txt", .{root_path});
    defer allocator.free(tracked_path);
    try source_dir.writeFile(.{
        .sub_path = "tracked/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        .data = tracked_path,
    });
    try source_dir.makePath("objects/aa");
    try source_dir.writeFile(.{
        .sub_path = "objects/aa/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        .data = "content\n",
    });

    const source_store_path = try tmp.dir.realpathAlloc(allocator, "source/.omohi");
    defer allocator.free(source_store_path);
    const archive_parent = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(archive_parent);
    const archive_path = try std.fs.path.join(allocator, &.{ archive_parent, "backup.tar.gz" });
    defer allocator.free(archive_path);

    _ = try backup.writeBackup(allocator, source_dir, .{
        .store_path = source_store_path,
        .archive_path = archive_path,
        .max_size = 1024 * 1024,
    });

    try tmp.dir.makePath("dest");
    const dest_store_path = try std.fs.path.join(allocator, &.{ archive_parent, "dest", ".omohi" });
    defer allocator.free(dest_store_path);

    var result = try restoreBackup(allocator, .{
        .store_path = dest_store_path,
        .archive_path = archive_path,
        .replace_existing = false,
        .max_size = 1024 * 1024,
    });
    defer freeRestoreResult(allocator, &result);

    try std.testing.expect(result.entry_count > 0);
    try std.testing.expectEqual(@as(usize, 1), result.missing_tracked_count);
    try std.testing.expectEqual(@as(?[]u8, null), result.rollback_path);

    var restored = try std.fs.openDirAbsolute(dest_store_path, .{ .iterate = true, .access_sub_paths = true });
    defer restored.close();
    const version = try restored.readFileAlloc(allocator, "VERSION", 16);
    defer allocator.free(version);
    try std.testing.expectEqualStrings("1\n", version);

    const tracked = try restored.readFileAlloc(allocator, "tracked/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", 512);
    defer allocator.free(tracked);
    try std.testing.expectEqualStrings(tracked_path, tracked);
}

test "restoreBackup rejects non-empty target without replace" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const root_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);
    const archive_path = try std.fs.path.join(allocator, &.{ root_path, "missing.tar.gz" });
    defer allocator.free(archive_path);

    var existing = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer existing.close();
    try existing.writeFile(.{ .sub_path = "VERSION", .data = "1\n" });

    const store_path = try tmp.dir.realpathAlloc(allocator, ".omohi");
    defer allocator.free(store_path);

    try std.testing.expectError(error.RestoreTargetExists, restoreBackup(allocator, .{
        .store_path = store_path,
        .archive_path = archive_path,
        .replace_existing = false,
        .max_size = 1024,
    }));
}

test "restoreBackup rejects oversized and invalid archives" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const root_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);
    const archive_path = try std.fs.path.join(allocator, &.{ root_path, "invalid.tar.gz" });
    defer allocator.free(archive_path);
    try tmp.dir.writeFile(.{ .sub_path = "invalid.tar.gz", .data = "not gzip" });
    try tmp.dir.makePath("dest");
    const store_path = try std.fs.path.join(allocator, &.{ root_path, "dest", ".omohi" });
    defer allocator.free(store_path);

    try std.testing.expectError(error.RestoreTooLarge, restoreBackup(allocator, .{
        .store_path = store_path,
        .archive_path = archive_path,
        .replace_existing = false,
        .max_size = 1,
    }));
    try std.testing.expectError(error.InvalidRestoreArchive, restoreBackup(allocator, .{
        .store_path = store_path,
        .archive_path = archive_path,
        .replace_existing = false,
        .max_size = 1024,
    }));
}

test "restoreBackup replaces non-empty target and leaves rollback directory" {
    const backup = @import("./backup.zig");

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var source_dir = try tmp.dir.makeOpenPath("source/.omohi", .{ .iterate = true, .access_sub_paths = true });
    defer source_dir.close();
    try source_dir.writeFile(.{ .sub_path = "VERSION", .data = "1\n" });
    try source_dir.makePath("tracked");

    const root_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);
    const source_store_path = try tmp.dir.realpathAlloc(allocator, "source/.omohi");
    defer allocator.free(source_store_path);
    const archive_path = try std.fs.path.join(allocator, &.{ root_path, "backup.tar.gz" });
    defer allocator.free(archive_path);
    _ = try backup.writeBackup(allocator, source_dir, .{
        .store_path = source_store_path,
        .archive_path = archive_path,
        .max_size = 1024 * 1024,
    });

    var existing = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer existing.close();
    try existing.writeFile(.{ .sub_path = "VERSION", .data = "old\n" });

    const store_path = try tmp.dir.realpathAlloc(allocator, ".omohi");
    defer allocator.free(store_path);

    var result = try restoreBackup(allocator, .{
        .store_path = store_path,
        .archive_path = archive_path,
        .replace_existing = true,
        .max_size = 1024 * 1024,
    });
    defer freeRestoreResult(allocator, &result);

    try std.testing.expect(result.rollback_path != null);
    var rollback = try std.fs.openDirAbsolute(result.rollback_path.?, .{});
    defer rollback.close();
    const old_version = try rollback.readFileAlloc(allocator, "VERSION", 16);
    defer allocator.free(old_version);
    try std.testing.expectEqualStrings("old\n", old_version);
}
