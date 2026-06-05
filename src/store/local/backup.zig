const std = @import("std");

const gzip_store = @import("../storage/gzip_store.zig");

const default_backup_root = ".omohi";
const gzip_header_size = 10;
const gzip_footer_size = 8;
const gzip_block_payload_size = 32 * 1024;
const tar_block_size = 512;

/// Carries normalized paths and the archive size guard for backup creation.
pub const BackupOptions = struct {
    store_path: []const u8,
    archive_path: []const u8,
    max_size: u64,
};

/// Reports the completed archive size and number of archived store entries.
pub const BackupResult = struct {
    archive_size: u64,
    entry_count: usize,
};

const BackupEntry = struct {
    path: []u8,
    kind: Kind,
    size: u64,
    mtime: i128,

    const Kind = enum {
        directory,
        file,
    };
};

const BackupEntryList = std.array_list.Managed(BackupEntry);

/// Writes a gzip-compressed tar backup of the opened store directory.
/// Memory: borrowed options, temporary allocations are caller allocator-backed
/// Lifetime: returned result is independent of allocator
/// Errors: validation, size limit, and filesystem/archive write failures
/// Caller responsibilities: hold any required store lock before calling
pub fn writeBackup(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    options: BackupOptions,
) !BackupResult {
    if (isInsidePath(options.archive_path, options.store_path)) return error.BackupTargetInsideStore;

    var entries = try collectEntries(allocator, omohi_dir);
    defer freeEntries(allocator, &entries);
    sortEntries(entries.items);

    const estimated_size = try estimateArchiveSize(entries.items);
    if (estimated_size > options.max_size) return error.BackupTooLarge;

    return writeArchive(allocator, omohi_dir, options.archive_path, entries.items);
}

// Recursively collects backup entries while excluding LOCK and `.trash`.
fn collectEntries(allocator: std.mem.Allocator, omohi_dir: std.fs.Dir) !BackupEntryList {
    var entries = BackupEntryList.init(allocator);
    errdefer freeEntries(allocator, &entries);

    try collectDirEntries(allocator, omohi_dir, "", &entries);
    return entries;
}

// Collects entries below one relative directory path.
fn collectDirEntries(
    allocator: std.mem.Allocator,
    root_dir: std.fs.Dir,
    relative_dir_path: []const u8,
    entries: *BackupEntryList,
) !void {
    var dir = if (relative_dir_path.len == 0)
        try root_dir.openDir(".", .{ .iterate = true, .access_sub_paths = true })
    else
        try root_dir.openDir(relative_dir_path, .{ .iterate = true, .access_sub_paths = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (shouldSkipEntry(relative_dir_path, entry.name)) continue;

        const entry_path = try joinRelative(allocator, relative_dir_path, entry.name);
        errdefer allocator.free(entry_path);

        switch (entry.kind) {
            .directory => {
                const stat = try root_dir.statFile(entry_path);
                try entries.append(.{
                    .path = entry_path,
                    .kind = .directory,
                    .size = 0,
                    .mtime = stat.mtime,
                });
                try collectDirEntries(allocator, root_dir, entry_path, entries);
            },
            .file => {
                const stat = try root_dir.statFile(entry_path);
                try entries.append(.{
                    .path = entry_path,
                    .kind = .file,
                    .size = stat.size,
                    .mtime = stat.mtime,
                });
            },
            else => return error.UnsupportedBackupEntry,
        }
    }
}

// Reports entries that are deliberately excluded from backups.
fn shouldSkipEntry(relative_dir_path: []const u8, name: []const u8) bool {
    if (std.mem.eql(u8, name, ".trash")) return true;
    return relative_dir_path.len == 0 and std.mem.eql(u8, name, "LOCK");
}

// Writes the tar stream through gzip into an atomic destination file.
fn writeArchive(
    allocator: std.mem.Allocator,
    omohi_dir: std.fs.Dir,
    archive_path: []const u8,
    entries: []const BackupEntry,
) !BackupResult {
    const parent_path = std.fs.path.dirname(archive_path) orelse return error.InvalidPath;
    const archive_name = std.fs.path.basename(archive_path);
    if (archive_name.len == 0) return error.InvalidPath;

    var parent_dir = try std.fs.openDirAbsolute(parent_path, .{});
    defer parent_dir.close();

    if (parent_dir.access(archive_name, .{})) |_| {
        return error.BackupTargetExists;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    const tmp_name = try makeTempName(allocator, archive_name);
    defer allocator.free(tmp_name);

    {
        var file = try parent_dir.createFile(tmp_name, .{ .exclusive = true });
        errdefer file.close();
        errdefer parent_dir.deleteFile(tmp_name) catch {};

        var file_buffer: [32 * 1024]u8 = undefined;
        var file_writer = file.writer(&file_buffer);
        var gzip: gzip_store.Writer = undefined;
        try gzip.init(&file_writer.interface);

        var tar_writer = std.tar.Writer{ .underlying_writer = &gzip.interface };
        try tar_writer.setRoot(default_backup_root);
        for (entries) |entry| {
            switch (entry.kind) {
                .directory => try tar_writer.writeDir(entry.path, .{ .mtime = mtimeSeconds(entry.mtime) }),
                .file => try writeFileEntry(omohi_dir, &tar_writer, entry),
            }
        }
        try tar_writer.finishPedantically();
        try gzip.finish();
        try file.sync();
        file.close();
    }

    errdefer parent_dir.deleteFile(tmp_name) catch {};
    try parent_dir.rename(tmp_name, archive_name);
    try syncDir(parent_dir);

    const stat = try parent_dir.statFile(archive_name);
    return .{
        .archive_size = stat.size,
        .entry_count = entries.len,
    };
}

// Writes one regular file entry from the store into the tar stream.
fn writeFileEntry(root_dir: std.fs.Dir, tar_writer: *std.tar.Writer, entry: BackupEntry) !void {
    var file = try root_dir.openFile(entry.path, .{});
    defer file.close();

    var read_buffer: [32 * 1024]u8 = undefined;
    var reader = file.reader(&read_buffer);
    try tar_writer.writeFile(entry.path, &reader, entry.mtime);
}

// Estimates the final gzip file size conservatively before writing.
fn estimateArchiveSize(entries: []const BackupEntry) !u64 {
    var tar_size: u64 = tar_block_size; // root directory written by setRoot
    for (entries) |entry| {
        tar_size += try estimateTarEntrySize(entry);
    }
    tar_size += tar_block_size * 2; // pedantic tar EOF blocks

    const gzip_blocks = std.math.divCeil(u64, tar_size, gzip_block_payload_size) catch 0;
    return gzip_header_size + gzip_footer_size + tar_size + gzip_blocks * 5 + 5;
}

// Estimates tar bytes for one entry, including long-name extension when needed.
fn estimateTarEntrySize(entry: BackupEntry) !u64 {
    var size: u64 = tar_block_size;
    const full_path_len = default_backup_root.len + 1 + entry.path.len;
    if (full_path_len > 255) {
        size += tar_block_size + try paddedTarPayloadSize(full_path_len);
    }
    if (entry.kind == .file) {
        size += try paddedTarPayloadSize(entry.size);
    }
    return size;
}

// Rounds tar payload bytes up to the next 512-byte boundary.
fn paddedTarPayloadSize(size: u64) !u64 {
    const blocks = try std.math.divCeil(u64, size, tar_block_size);
    return blocks * tar_block_size;
}

// Sorts entries into deterministic path order.
fn sortEntries(entries: []BackupEntry) void {
    std.sort.block(BackupEntry, entries, {}, struct {
        fn lessThan(_: void, a: BackupEntry, b: BackupEntry) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.lessThan);
}

// Releases owned paths stored in the backup entry list.
fn freeEntries(allocator: std.mem.Allocator, entries: *BackupEntryList) void {
    for (entries.items) |entry| allocator.free(entry.path);
    entries.deinit();
}

// Joins relative store paths using the platform separator.
fn joinRelative(allocator: std.mem.Allocator, parent: []const u8, name: []const u8) ![]u8 {
    if (parent.len == 0) return allocator.dupe(u8, name);
    return std.fs.path.join(allocator, &.{ parent, name });
}

// Converts nanosecond mtime into tar seconds.
fn mtimeSeconds(mtime: i128) u64 {
    if (mtime <= 0) return 0;
    return @intCast(@divFloor(mtime, std.time.ns_per_s));
}

// Builds a collision-resistant temporary file name beside the destination.
fn makeTempName(allocator: std.mem.Allocator, archive_name: []const u8) ![]u8 {
    var random: [8]u8 = undefined;
    std.crypto.random.bytes(&random);
    var hex: [random.len * 2]u8 = undefined;
    encodeHexLower(&hex, &random);
    return std.fmt.allocPrint(allocator, ".{s}.tmp-{s}", .{ archive_name, hex });
}

// Encodes bytes into lowercase hex.
fn encodeHexLower(dest: []u8, source: []const u8) void {
    const alphabet = "0123456789abcdef";
    var idx: usize = 0;
    for (source) |byte| {
        dest[idx] = alphabet[@as(usize, byte >> 4)];
        dest[idx + 1] = alphabet[@as(usize, byte & 0x0f)];
        idx += 2;
    }
}

// Reports whether child is equal to or nested below parent.
fn isInsidePath(child: []const u8, parent: []const u8) bool {
    if (std.mem.eql(u8, child, parent)) return true;
    if (!std.mem.startsWith(u8, child, parent)) return false;
    if (child.len <= parent.len) return false;
    return child[parent.len] == std.fs.path.sep;
}

// Fsyncs a directory and tolerates platforms that reject directory fsync.
fn syncDir(dir: std.fs.Dir) !void {
    const rc = std.posix.system.fsync(dir.fd);
    switch (std.posix.errno(rc)) {
        .SUCCESS, .BADF, .INVAL, .ROFS => return,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}

test "writeBackup writes store files and excludes lock and trash" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try omohi_dir.writeFile(.{ .sub_path = "VERSION", .data = "1\n" });
    try omohi_dir.writeFile(.{ .sub_path = "LOCK", .data = "locked\n" });
    try omohi_dir.makePath("tracked/.trash");
    try omohi_dir.writeFile(.{ .sub_path = "tracked/live", .data = "/tmp/live\n" });
    try omohi_dir.writeFile(.{ .sub_path = "tracked/.trash/deleted", .data = "/tmp/deleted\n" });

    const store_path = try tmp.dir.realpathAlloc(allocator, ".omohi");
    defer allocator.free(store_path);
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    const archive_path = try std.fs.path.join(allocator, &.{ tmp_path, "backup.tar.gz" });
    defer allocator.free(archive_path);

    const result = try writeBackup(allocator, omohi_dir, .{
        .store_path = store_path,
        .archive_path = archive_path,
        .max_size = 1024 * 1024,
    });
    try std.testing.expect(result.archive_size > 0);

    const archive_bytes = try tmp.dir.readFileAlloc(allocator, "backup.tar.gz", 1024 * 1024);
    defer allocator.free(archive_bytes);
    var input: std.Io.Reader = .fixed(archive_bytes);
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    var inflate_buffer: [std.compress.flate.max_window_len]u8 = undefined;
    var inflater: std.compress.flate.Decompress = .init(&input, .gzip, &inflate_buffer);
    _ = try inflater.reader.streamRemaining(&output.writer);

    const tar_bytes = output.writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, tar_bytes, ".omohi/VERSION") != null);
    try std.testing.expect(std.mem.indexOf(u8, tar_bytes, ".omohi/tracked/live") != null);
    try std.testing.expect(std.mem.indexOf(u8, tar_bytes, "LOCK") == null);
    try std.testing.expect(std.mem.indexOf(u8, tar_bytes, ".trash") == null);
}

test "writeBackup rejects size limit before writing archive" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try omohi_dir.writeFile(.{ .sub_path = "VERSION", .data = "1\n" });

    const store_path = try tmp.dir.realpathAlloc(allocator, ".omohi");
    defer allocator.free(store_path);
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    const archive_path = try std.fs.path.join(allocator, &.{ tmp_path, "too-small.tar.gz" });
    defer allocator.free(archive_path);

    try std.testing.expectError(error.BackupTooLarge, writeBackup(allocator, omohi_dir, .{
        .store_path = store_path,
        .archive_path = archive_path,
        .max_size = 1,
    }));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access("too-small.tar.gz", .{}));
}

test "writeBackup rejects output inside store" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    var omohi_dir = try tmp.dir.makeOpenPath(".omohi", .{ .iterate = true, .access_sub_paths = true });
    defer omohi_dir.close();
    try omohi_dir.writeFile(.{ .sub_path = "VERSION", .data = "1\n" });

    const store_path = try tmp.dir.realpathAlloc(allocator, ".omohi");
    defer allocator.free(store_path);
    const archive_path = try std.fs.path.join(allocator, &.{ store_path, "backup.tar.gz" });
    defer allocator.free(archive_path);

    try std.testing.expectError(error.BackupTargetInsideStore, writeBackup(allocator, omohi_dir, .{
        .store_path = store_path,
        .archive_path = archive_path,
        .max_size = 1024 * 1024,
    }));
}
